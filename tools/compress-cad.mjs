// Compress a CAD glb while keeping COLOR_0 vertex colours.
//
// The trick: CAD exporters give every triangle its own vertices because each
// face carries its own normals. That blocks vertex welding, which in turn
// blocks the simplifier. Dropping NORMAL lets vertices merge by position and
// colour; three.js then computes flat normals at load, which is what you want
// for CAD anyway.
//
//   node compress-cad.mjs in.glb out.glb [targetTriangles]

import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, dedup, prune, draco, normals } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import draco3d from 'draco3dgltf';

const [,, inFile, outFile, targetArg] = process.argv;
const TARGET = Number(targetArg ?? 300_000);   // triangles, not a percentage

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({
    'draco3d.encoder': await draco3d.createEncoderModule(),
    'draco3d.decoder': await draco3d.createDecoderModule(),
  });

const doc = await io.read(inFile);

const count = () => doc.getRoot().listMeshes()
  .flatMap(m => m.listPrimitives())
  .reduce((n, p) => n + (p.getIndices()?.getCount() ?? p.getAttribute('POSITION').getCount()) / 3, 0);

const attrs = () => doc.getRoot().listMeshes()
  .flatMap(m => m.listPrimitives())
  .flatMap(p => p.listSemantics());

console.log('in :', Math.round(count()).toLocaleString(), 'tris |', [...new Set(attrs())].join(', '));

// 1. drop NORMAL so vertices can actually merge
for (const mesh of doc.getRoot().listMeshes())
  for (const prim of mesh.listPrimitives())
    prim.setAttribute('NORMAL', null);

// 2. weld — now effective, and COLOR_0 rides along
await doc.transform(weld());
console.log('welded');

// 3. reduce to the target triangle count.
//    The simplifier's error bound is relative to each part's own size, so on an
//    assembly of many small components a tight bound means nothing collapses at
//    all. Start tight to preserve shape, loosen only as far as needed.
await MeshoptSimplifier.ready;
for (const error of [0.001, 0.01, 0.05, 0.2, 0.5, 1]) {
  const have = count();
  if (have <= TARGET * 1.05) break;
  await doc.transform(
    simplify({ simplifier: MeshoptSimplifier, ratio: TARGET / have, error }),
    dedup(),
    prune(),
  );
  console.log(`  error ${error}: ${Math.round(have).toLocaleString()} -> ${Math.round(count()).toLocaleString()}`);
}

// 3b. put normals back. Without them three.js has nothing to light the
// surface with and everything renders flat grey.
await doc.transform(normals({ overwrite: true }));
console.log('out:', Math.round(count()).toLocaleString(), `tris (target ${TARGET.toLocaleString()}) |`, [...new Set(attrs())].join(', '));

// 4. compress
await doc.transform(draco());
await io.write(outFile, doc);
