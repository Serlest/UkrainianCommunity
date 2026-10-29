interface ContentStorageObject {
  delete(options:{ignoreNotFound:true}):Promise<unknown>;
}

/** A concurrent lifecycle worker may delete a listed object first. Only that
 * per-object absence is harmless; listing, permission and provider errors still
 * propagate. Keep the queue bounded instead of collecting an entire prefix. */
export async function deleteListedContentStorageObjects(files:AsyncIterable<ContentStorageObject>):Promise<void> {
  let batch:ContentStorageObject[]=[];
  const flush=async () => { await Promise.all(batch.map(file=>file.delete({ignoreNotFound:true})));batch=[]; };
  for await (const file of files) {
    batch.push(file);
    if (batch.length===10) await flush();
  }
  if (batch.length) await flush();
}
