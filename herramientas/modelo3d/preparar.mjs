#!/usr/bin/env node
// =========================================================
// Preparación de modelos 3D para el visor de la plataforma (docs/modelos-3d.md, D51)
//
//   node preparar.mjs <entrada.glb> <salida.glb> [--excluir "Categoría 1,Categoría 2"]
//
// Entrada: GLB exportado de Revit (Leia u otro exportador glTF) o de Blender.
// Salida:  GLB listo para subir, más <salida>.informe.json con el informe de validación.
//
// Pasos (siempre los mismos, para que todos los modelos se comporten igual):
//   1. Lee el modelo (con o sin Draco) y lleva todo a metros con la Y hacia arriba.
//   2. De cada elemento conserva solo: identificador de Revit, categoría, nivel y tipo.
//   3. Calcula la cota de cada nivel y asigna nivel por altura a lo que no lo trae.
//   4. Agrupa la geometría por nivel y material (pocos objetos = visor fluido) y guarda en
//      cada vértice el número de elemento (_ID) para saber qué se ha pulsado.
//   5. Unifica materiales repetidos y comprime con Draco.
//   6. Escribe el informe: tamaño, triángulos, niveles con su cota, categorías y avisos.
// =========================================================
import { readFile, stat, writeFile } from 'node:fs/promises'
import { basename } from 'node:path'
import { Accessor, NodeIO, Primitive } from '@gltf-transform/core'
import { ALL_EXTENSIONS } from '@gltf-transform/extensions'
import { dedup, prune, draco } from '@gltf-transform/functions'
import draco3d from 'draco3dgltf'

// ---------- límites (los mismos que comprobará la plataforma al subir) ----------
const LIMITES = {
  tamanoMaxMb: 40,           // Supabase gratuito admite 50 MB por archivo
  triangulosAviso: 1_500_000,
  triangulosMax: 3_000_000,
  alturaMinM: 2,             // menos: probablemente unidades equivocadas
  alturaMaxM: 500,
}
// Parámetros donde Revit (en español o en inglés) guarda el nivel de un elemento
const CLAVES_NIVEL = ['Nivel', 'Level', 'Restricción de base', 'Base Constraint', 'Nivel base', 'Base Level',
  'Nivel de referencia', 'Reference Level', 'Nivel de planta', 'Schedule Level', 'planta', 'nivel']
const CLAVES_CATEGORIA = ['Category', 'Categoría', 'categoria']

function argumentos() {
  const a = process.argv.slice(2)
  const pos = a.filter((x, i) => !x.startsWith('--') && !(a[i - 1] ?? '').startsWith('--'))
  const i = a.indexOf('--excluir')
  const excluir = i >= 0 ? a[i + 1].split(',').map((s) => s.trim()).filter(Boolean) : []
  if (pos.length < 2) {
    console.error('Uso: node preparar.mjs <entrada.glb> <salida.glb> [--excluir "Categoría 1,Categoría 2"]')
    process.exit(2)
  }
  return { entrada: pos[0], salida: pos[1], excluir }
}

const primero = (obj, claves) => { for (const k of claves) if (obj?.[k] != null && obj[k] !== '') return String(obj[k]); return null }
const mediana = (v) => { const s = [...v].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : null }
const mb = (b) => Math.round(b / 1048576 * 10) / 10

// Transforma un punto o una dirección por una matriz 4×4 (column-major, como glTF)
function porMatriz(m, x, y, z, w) {
  return [m[0] * x + m[4] * y + m[8] * z + m[12] * w, m[1] * x + m[5] * y + m[9] * z + m[13] * w,
          m[2] * x + m[6] * y + m[10] * z + m[14] * w]
}

async function main() {
  const { entrada, salida, excluir } = argumentos()
  const avisos = []
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
    'draco3d.decoder': await draco3d.createDecoderModule(),
    'draco3d.encoder': await draco3d.createEncoderModule(),
  })
  const doc = await io.read(entrada)
  const raiz = doc.getRoot()
  const escena = raiz.getDefaultScene() ?? raiz.listScenes()[0]

  // ---------- 1-2. elementos en metros, con Y arriba ----------
  const elementos = []        // { id, categoria, nivel, tipo, minY, partes: [{ primitiva, matriz }] }
  const excluidos = new Map()
  escena.traverse((nodo) => {
    const malla = nodo.getMesh()
    if (!malla) return
    const extras = nodo.getExtras() ?? {}
    const par = extras.parameters ?? extras
    const nombre = nodo.getName() ?? ''
    const categoria = primero(par, CLAVES_CATEGORIA) ?? nombre.split(' ')[0] ?? 'Sin categoría'
    if (excluir.includes(categoria)) { excluidos.set(categoria, (excluidos.get(categoria) ?? 0) + 1); return }
    const m = nombre.match(/<(\d+)\s+([^<]*)</)          // Leia: "Wall Muros <619340 Tipo<"
    const matriz = nodo.getWorldMatrix()
    let minY = Infinity
    for (const p of malla.listPrimitives()) {
      const pos = p.getAttribute('POSITION')
      for (let i = 0; i < pos.getCount(); i++) {
        const v = pos.getElement(i, [])
        const y = porMatriz(matriz, v[0], v[1], v[2], 1)[1]
        if (y < minY) minY = y
      }
    }
    elementos.push({
      id: m ? Number(m[1]) : (par.ElementId ?? par.UniqueId ?? nombre),
      categoria, nivel: primero(par, CLAVES_NIVEL), tipo: m ? m[2].trim() : nombre,
      minY, partes: malla.listPrimitives().map((primitiva) => ({ primitiva, matriz })),
    })
  })
  if (!elementos.length) throw new Error('El modelo no tiene geometría')
  if (elementos.length > 65535) throw new Error(`${elementos.length} elementos: el máximo es 65.535. Oculte categorías de detalle en la vista de exportación.`)

  // ---------- 3. niveles: cota = mediana de la base de sus elementos ----------
  const porNivel = new Map()
  for (const e of elementos) if (e.nivel) (porNivel.get(e.nivel) ?? porNivel.set(e.nivel, []).get(e.nivel)).push(e.minY)
  const niveles = [...porNivel].map(([nombre, ys]) => ({ nombre, cota: Math.round(mediana(ys) * 100) / 100 }))
    .sort((a, b) => a.cota - b.cota)
  let sinNivel = 0
  for (const e of elementos) {
    if (e.nivel) continue
    sinNivel++
    // el nivel más alto cuya cota no supera la base del elemento (+ 0,5 m de tolerancia)
    const n = [...niveles].reverse().find((x) => x.cota <= e.minY + 0.5) ?? niveles[0]
    e.nivel = n?.nombre ?? 'Sin nivel'
    e.nivelPorAltura = true
  }
  if (!niveles.length) avisos.push({ nivel: 'AVISO', texto: 'Ningún elemento trae nivel: el visor no podrá mostrar el edificio planta a planta. Exporte con los niveles (Leia: Export Levels y Export Properties).' })

  // ---------- 4. agrupar por nivel y material, con el número de elemento en cada vértice ----------
  const grupos = new Map()
  elementos.forEach((e, indice) => {
    for (const { primitiva, matriz } of e.partes) {
      const material = primitiva.getMaterial()
      const clave = `${e.nivel}|${material?.getName() ?? ''}|${raiz.listMaterials().indexOf(material)}`
      if (!grupos.has(clave)) grupos.set(clave, { nivel: e.nivel, material, partes: [] })
      grupos.get(clave).partes.push({ primitiva, matriz, indice })
    }
  })
  const buffer = raiz.listBuffers()[0] ?? doc.createBuffer()
  const nuevaEscena = doc.createScene('Edificio')
  for (const [, g] of grupos) {
    let nv = 0, ni = 0
    for (const { primitiva } of g.partes) {
      nv += primitiva.getAttribute('POSITION').getCount()
      ni += primitiva.getIndices()?.getCount() ?? primitiva.getAttribute('POSITION').getCount()
    }
    // _ID como entero de 16 bits: Draco comprime los enteros sin pérdida (los decimales los redondea)
    const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3), ids = new Uint16Array(nv)
    const idx = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni)
    let ov = 0, oi = 0
    for (const { primitiva, matriz, indice } of g.partes) {
      const P = primitiva.getAttribute('POSITION'), N = primitiva.getAttribute('NORMAL'), I = primitiva.getIndices()
      const n = P.getCount()
      for (let i = 0; i < n; i++) {
        const v = P.getElement(i, []); const w = porMatriz(matriz, v[0], v[1], v[2], 1)
        pos.set(w, (ov + i) * 3)
        if (N) {
          const d = N.getElement(i, []); const t = porMatriz(matriz, d[0], d[1], d[2], 0)
          const l = Math.hypot(t[0], t[1], t[2]) || 1
          nor.set([t[0] / l, t[1] / l, t[2] / l], (ov + i) * 3)
        }
        ids[ov + i] = indice
      }
      if (I) for (let i = 0; i < I.getCount(); i++) idx[oi + i] = I.getScalar(i) + ov
      else for (let i = 0; i < n; i++) idx[oi + i] = ov + i
      ov += n; oi += I ? I.getCount() : n
    }
    const prim = doc.createPrimitive().setMode(Primitive.Mode.TRIANGLES).setMaterial(g.material)
      .setAttribute('POSITION', doc.createAccessor().setType(Accessor.Type.VEC3).setArray(pos).setBuffer(buffer))
      .setAttribute('NORMAL', doc.createAccessor().setType(Accessor.Type.VEC3).setArray(nor).setBuffer(buffer))
      .setAttribute('_ID', doc.createAccessor().setType(Accessor.Type.SCALAR).setArray(ids).setBuffer(buffer))
      .setIndices(doc.createAccessor().setType(Accessor.Type.SCALAR).setArray(idx).setBuffer(buffer))
    const malla = doc.createMesh(`${g.nivel} · ${g.material?.getName() ?? 'sin material'}`).addPrimitive(prim)
    nuevaEscena.addChild(doc.createNode(malla.getName()).setMesh(malla).setExtras({ nivel: g.nivel }))
  }
  // Sustituye la escena original por la agrupada
  for (const s of raiz.listScenes()) if (s !== nuevaEscena) s.dispose()
  raiz.setDefaultScene(nuevaEscena)
  for (const n of raiz.listNodes()) if (!nuevaEscena.listChildren().includes(n)) n.dispose()

  // ---------- medidas, comprobaciones y datos para el visor ----------
  let triangulos = 0
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity]
  for (const n of nuevaEscena.listChildren()) for (const p of n.getMesh().listPrimitives()) {
    triangulos += p.getIndices().getCount() / 3
    const a = p.getAttribute('POSITION'); const lo = a.getMin([]), hi = a.getMax([])
    for (let k = 0; k < 3; k++) { min[k] = Math.min(min[k], lo[k]); max[k] = Math.max(max[k], hi[k]) }
  }
  const dim = max.map((v, k) => Math.round((v - min[k]) * 10) / 10)
  if (triangulos > LIMITES.triangulosMax) avisos.push({ nivel: 'ERROR', texto: `${triangulos.toLocaleString('es-ES')} triángulos: demasiados para el navegador (máx. ${LIMITES.triangulosMax.toLocaleString('es-ES')}). Oculte barandillas, mobiliario, equipos y vegetación en la vista de exportación.` })
  else if (triangulos > LIMITES.triangulosAviso) avisos.push({ nivel: 'AVISO', texto: `${triangulos.toLocaleString('es-ES')} triángulos: puede ir lento en portátiles. Revise las categorías que más pesan.` })
  if (dim[1] < LIMITES.alturaMinM || dim[1] > LIMITES.alturaMaxM) avisos.push({ nivel: 'ERROR', texto: `Altura del edificio de ${dim[1]} m: revise las unidades (deben ser metros) o la orientación (Leia: Flip YZ-Axis).` })
  if (dim[1] > Math.max(dim[0], dim[2]) * 3) avisos.push({ nivel: 'AVISO', texto: 'El modelo es mucho más alto que ancho: puede que esté tumbado (Leia: Flip YZ-Axis).' })
  if (sinNivel) avisos.push({ nivel: 'INFO', texto: `${sinNivel} elementos sin nivel en sus parámetros (montantes, paneles, barandillas…): se les ha asignado por altura.` })

  const conteoNivel = new Map(), conteoCat = new Map()
  for (const e of elementos) {
    conteoNivel.set(e.nivel, (conteoNivel.get(e.nivel) ?? 0) + 1)
    conteoCat.set(e.categoria, (conteoCat.get(e.categoria) ?? 0) + 1)
  }
  const nivelesInforme = niveles.map((n) => ({ ...n, elementos: conteoNivel.get(n.nombre) ?? 0 }))
  nuevaEscena.setExtras({
    plataforma: {
      version: 1, unidades: 'm', arriba: 'Y',
      limites: { min: min.map((v) => Math.round(v * 100) / 100), max: max.map((v) => Math.round(v * 100) / 100) },
      niveles: niveles.map((n) => ({ nombre: n.nombre, cota: n.cota })),
      // Por número de elemento (_ID): [identificador de Revit, categoría, nivel, tipo]
      elementos: elementos.map((e) => [e.id, e.categoria, e.nivel, e.tipo]),
    },
  })

  // ---------- 5. materiales repetidos, limpieza y compresión ----------
  await doc.transform(dedup(), prune(), draco({ method: 'edgebreaker' }))
  raiz.getAsset().generator = 'preparar-modelo3d 1.0 (plataforma energética)'
  await io.write(salida, doc)

  // ---------- 6. informe ----------
  const [te, ts] = [(await stat(entrada)).size, (await stat(salida)).size]
  if (mb(ts) > LIMITES.tamanoMaxMb) avisos.push({ nivel: 'ERROR', texto: `El modelo preparado pesa ${mb(ts)} MB (máx. ${LIMITES.tamanoMaxMb} MB).` })
  const informe = {
    archivo: basename(entrada), fecha: new Date().toISOString(),
    tamano_mb: { entrada: mb(te), salida: mb(ts) },
    elementos: elementos.length, excluidos: Object.fromEntries(excluidos), triangulos,
    objetos_en_visor: nuevaEscena.listChildren().length, materiales: raiz.listMaterials().length,
    dimensiones_m: { ancho: dim[0], alto: dim[1], fondo: dim[2] },
    niveles: nivelesInforme,
    categorias: Object.fromEntries([...conteoCat].sort((a, b) => b[1] - a[1])),
    avisos, valido: !avisos.some((a) => a.nivel === 'ERROR'),
  }
  await writeFile(salida.replace(/\.glb$/i, '') + '.informe.json', JSON.stringify(informe, null, 2))

  console.log(`\n${informe.valido ? '✔ Modelo válido' : '✘ Modelo NO válido'} · ${informe.archivo}`)
  console.log(`  Tamaño: ${informe.tamano_mb.entrada} MB → ${informe.tamano_mb.salida} MB`)
  console.log(`  ${elementos.length} elementos · ${triangulos.toLocaleString('es-ES')} triángulos · ${informe.objetos_en_visor} objetos en el visor · ${informe.materiales} materiales`)
  console.log(`  Dimensiones: ${dim[0]} × ${dim[2]} m, ${dim[1]} m de alto`)
  console.log('  Niveles:'); for (const n of nivelesInforme) console.log(`    ${String(n.cota).padStart(7)} m  ${n.nombre} (${n.elementos} elementos)`)
  for (const a of avisos) console.log(`  [${a.nivel}] ${a.texto}`)
  process.exit(informe.valido ? 0 : 1)
}

main().catch((e) => { console.error('Error:', e.message); process.exit(1) })
