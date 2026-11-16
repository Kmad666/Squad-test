// Runs the Kettenkiez layout code headless and records where things are.
const fs = require("fs"), path = require("path");
const src = process.argv[2];
globalThis.THREE = require("three");
const noop = new Proxy(function () {}, { get: (t, k) => (k === Symbol.toPrimitive ? () => 0 : noop), apply: () => noop, construct: () => noop, set: () => true });
globalThis.document = { createElement: () => ({ width: 0, height: 0, getContext: () => noop, style: {} }) };
globalThis.TEX = new Proxy({}, { get: (t, k) => t[k] ?? { size: [1, 1], map: null, normal: null }, set: (t, k, v) => (t[k] = v, true) });
globalThis.MAT = {};
globalThis.SCHEMES = new Array(20).fill({});
const REC = { lots: [], cars: [], lamps: [], trees: [], bollards: [], bins: [], misc: [], bikes: [] };
globalThis.REC = REC;
let code = "";
for (const f of ["00_util.js", "50_street.js", "60_props.js", "65_trees.js", "66_cars.js", "67_tram_bikes.js", "70_district.js"]) code += fs.readFileSync(path.join(src, f), "utf8") + "\n";
code += `
toTex = () => null; globalThis.orientUp = g => g;
const _car = car; car = function (B, x, z, h, rng) { const len = _car(B, x, z, h, rng); REC.cars.push({ x, z, h, len }); return len; };
const _lamp = gasLamp; gasLamp = function (B, x, z, r) { REC.lamps.push({ x, z }); return _lamp(B, x, z, r); };
const _tree = treeGeometry; treeGeometry = function (x, z, rng, B, cards, s) { REC.trees.push({ x, z, s: s ?? 1 }); return _tree(x, z, rng, B, cards, s); };
const _lit = litfass; litfass = function (B, x, z) { REC.misc.push({ what: "litfass", x, z }); return _lit(B, x, z); };
const _pump = pump; pump = function (B, x, z, r) { REC.misc.push({ what: "pump", x, z }); return _pump(B, x, z, r); };
const _stop = tramStop; tramStop = function (B, x, z) { REC.misc.push({ what: "tramstop", x, z }); return _stop(B, x, z); };
const _bol = bollard; bollard = function (B, x, z) { REC.bollards.push({ x, z }); return _bol(B, x, z); };
const _bin = bin; bin = function (B, x, z, r) { REC.bins.push({ x, z }); return _bin(B, x, z, r); };
const _tram = tram; tram = function (B, xf, zt, dir) { REC.misc.push({ what: "tram", xFront: xf, z: zt, dir }); return _tram(B, xf, zt, dir); };
const _bike = bicycle; bicycle = function (B, x, z, a, rng) { REC.bikes.push({ x, z, a }); return _bike(B, x, z, a, rng); };
const out = buildDistrict(null);
for (const j of out.jobs) {
  if (j.gap) REC.lots.push({ gap: true, street: j.street, quadrant: j.quadrant, segs: [{ o: [j.seg.origin.x, j.seg.origin.z], a: [j.seg.along.x, j.seg.along.z], w: j.seg.width }] });
  else REC.lots.push({ name: j.name, style: j.style, gateWide: !!j.gateWide, corner: j.corner, segs: j.segments.map(s => ({ o: [s.origin.x, s.origin.z], a: [s.along.x, s.along.z], w: s.width, chamfer: !!s.chamfer })) });
}
for (const j of out.jobs) if (j.gap) { try { buildGap(j, new Bucket()); } catch (e) { REC.err_gap = String(e); } }
for (const [n, f] of [["props", buildProps], ["cars", buildCars], ["tram", buildTramAndBikes], ["trees", buildTrees]]) { try { f(); } catch (e) { REC["err_" + n] = String(e).slice(0, 200); } }
REC.D = D; REC.gapGreen = { trees: GAP_GREEN.trees.map(p => [p.x, p.z]), bushes: GAP_GREEN.bushes.map(p => [p.x, p.z]) };
`;
new Function(code)();
fs.writeFileSync(process.argv[3], JSON.stringify(REC, null, 1));
console.log(Object.entries(REC).map(([k, v]) => k + ":" + (Array.isArray(v) ? v.length : JSON.stringify(v).slice(0, 120))).join("\n"));
