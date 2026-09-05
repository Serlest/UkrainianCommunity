import {type BulkWriter, type DocumentData, type DocumentReference, type UpdateData} from "firebase-admin/firestore";

import {db} from "./admin";

/** BulkWriter.close() only drains the queue; every individual write must also succeed. */
export class CheckedBulkWriter {
  private readonly pending: Promise<void>[] = [];
  private readonly failures: unknown[] = [];

  constructor(private readonly writer: BulkWriter = db.bulkWriter()) {}

  delete(reference: DocumentReference): void {
    this.observe(this.writer.delete(reference));
  }

  update(reference: DocumentReference, data: UpdateData<DocumentData>): void {
    this.observe(this.writer.update(reference, data));
  }

  private observe(operation: Promise<unknown>): void {
    // Install the rejection handler immediately, including while callers load
    // subsequent pages. A later close must never conceal a failed write.
    this.pending.push(operation.then(() => undefined, (error: unknown) => {
      this.failures.push(error);
    }));
  }

  async close(): Promise<void> {
    try {
      await this.writer.close();
    } finally {
      await Promise.all(this.pending);
    }
    if (this.failures.length > 0) throw this.failures[0];
  }
}
