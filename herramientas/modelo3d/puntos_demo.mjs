// Calcula puntos de etiqueta sobre paredes reales del modelo de demostración (solo para
// docs/demo_torre_modelo3d.sql). Para cada recinto: busca el suelo bajo un punto interior,
// lanza rayos horizontales a 1,5 m y elige la pared más larga y cercana; reparte hasta 8 puntos
// sobre ella (cada 1,6 m, alternando 1,3 y 1,9 m de altura), 3 cm por delante de la superficie.
//   node puntos_demo.mjs <modelo-preparado.glb>
import { NodeIO } from '@gltf-transform/core'
import { ALL_EXTENSIONS } from '@gltf-transform/extensions'
import draco3d from 'draco3dgltf'

const RECINTOS = [   // código, x, z, cota aproximada del suelo
  ['APARCAMIENTO', 0, 0, 1.8], ['CUARTO-CONT', -4, -10, 6.0], ['VESTIBULO', 6, -5, 6.0], ['LOCAL', -20, -4, 5.2],
  ['OFICINAS-P1', -18, -10.5, 8.7], ['OFICINAS-P2', 0, -4, 9.5], ['OFICINAS-P3', 0, -4, 12.7], ['OFICINAS-P4', 0, -4, 16.8],
  ['OFICINAS-P5', 0, -4, 20.9], ['ZONA-TEC', 3.5, 4, 23.4], ['SALA-CALDERAS', -10, -6, 24.9],
]
const PAREDES = new Set(['Muros', 'Walls', 'Paneles de muro cortina', 'Curtain Panels'])

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({ 'draco3d.decoder': await draco3d.createDecoderModule() })
const doc = await io.read(process.argv[2])
const elementos = doc.getRoot().listScenes()[0].getExtras().plataforma.elementos
const tri = []   // [ax,ay,az,bx,by,bz,cx,cy,cz,categoria]
for (const nodo of doc.getRoot().listNodes()) {
  const malla = nodo.getMesh(); if (!malla) continue
  for (const p of malla.listPrimitives()) {
    const pos = p.getAttribute('POSITION'), ids = p.getAttribute('_ID'), ind = p.getIndices()
    const n = ind ? ind.getCount() : pos.getCount()
    const v = [0, 0, 0]
    for (let i = 0; i < n; i += 3) {
      const t = []
      for (let k = 0; k < 3; k++) { pos.getElement(ind ? ind.getScalar(i + k) : i + k, v); t.push(...v) }
      t.push(elementos[ids.getScalar(ind ? ind.getScalar(i) : i)]?.[1] ?? '')
      tri.push(t)
    }
  }
}
// Möller–Trumbore
function rayo(o, d, filtro) {
  let mejor = null
  for (const t of tri) {
    if (filtro && !filtro(t[9])) continue
    const e1 = [t[3] - t[0], t[4] - t[1], t[5] - t[2]], e2 = [t[6] - t[0], t[7] - t[1], t[8] - t[2]]
    const p = [d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2], d[0] * e2[1] - d[1] * e2[0]]
    const det = e1[0] * p[0] + e1[1] * p[1] + e1[2] * p[2]
    if (Math.abs(det) < 1e-9) continue
    const s = [o[0] - t[0], o[1] - t[1], o[2] - t[2]]
    const u = (s[0] * p[0] + s[1] * p[1] + s[2] * p[2]) / det; if (u < 0 || u > 1) continue
    const q = [s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0]]
    const w = (d[0] * q[0] + d[1] * q[1] + d[2] * q[2]) / det; if (w < 0 || u + w > 1) continue
    const dist = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) / det
    if (dist > 0.01 && (!mejor || dist < mejor.dist)) mejor = { dist, cat: t[9] }
  }
  return mejor
}
const r2 = (x) => Math.round(x * 100) / 100
const salida = []
for (const [codigo, x, z, cota] of RECINTOS) {
  const suelo = rayo([x, cota + 1.0, z], [0, -1, 0])
  const y0 = suelo && suelo.dist < 2.5 ? cota + 1.0 - suelo.dist : cota
  // De 16 direcciones, la pared más larga y plana (más puntos alineados); a igualdad, la más cercana.
  // Los puntos van en una fila cada 1,6 m, alternando 1,3 y 1,9 m de altura para que los valores no se tapen.
  const OFFS = [-3.5, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3.5].map((k) => k * 1.6)
  let pared = null
  for (let a = 0; a < 16; a++) {
    const d = [Math.cos(a * Math.PI / 8), 0, Math.sin(a * Math.PI / 8)]
    const h = rayo([x, y0 + 1.5, z], d, (c) => PAREDES.has(c))
    if (!h || h.dist > 12) continue
    const tng = [-d[2], 0, d[0]]
    const pts = OFFS.map((k, i) => {
      const o = [x + tng[0] * k, y0 + (i % 2 ? 1.9 : 1.3), z + tng[2] * k]
      const hh = rayo(o, d, (c) => PAREDES.has(c))
      return hh && Math.abs(hh.dist - h.dist) < 0.5 ? [r2(o[0] + d[0] * (hh.dist - 0.03)), r2(o[1]), r2(o[2] + d[2] * (hh.dist - 0.03))] : null
    })
    const buenos = pts.filter(Boolean)
    if (!pared || buenos.length > pared.n || (buenos.length === pared.n && h.dist < pared.dist)) pared = { ...h, d, n: buenos.length, pts }
  }
  const puntos = []
  if (pared && pared.n >= 5) {
    // primero los puntos sobre la pared, del centro hacia fuera
    const orden = [3, 4, 2, 5, 1, 6, 0, 7]
    for (const i of orden) if (pared.pts[i]) puntos.push(pared.pts[i])
  } else {
    pared = null
    for (const fila of [-0.8, 0.8]) for (const k of [-2.4, -0.8, 0.8, 2.4]) puntos.push([r2(x + k), r2(y0 + 0.05), r2(z + fila)])
  }
  salida.push({ codigo, suelo: r2(y0), pared: pared ? `${pared.cat} a ${r2(pared.dist)} m, ${pared.n} puntos` : 'sin pared: sobre el suelo', puntos })
}
console.log(JSON.stringify(salida, null, 1))
