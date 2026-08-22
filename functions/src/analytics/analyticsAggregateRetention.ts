const preservedDocumentIDs = new Set(["today", "seven_days", "thirty_days"]);

export function shouldDeleteAggregateDocument(
  documentID: string,
  cutoffDate: Date,
): boolean {
  if (preservedDocumentIDs.has(documentID)) {
    return false;
  }

  const documentDate = dateFromDocumentID(documentID);
  return documentDate !== undefined && documentDate < cutoffDate;
}

export function dateFromDocumentID(documentID: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(documentID);
  if (!match) {
    return undefined;
  }

  const [, yearValue, monthValue, dayValue] = match;
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  const date = new Date(Date.UTC(year, month - 1, day));

  if (
    date.getUTCFullYear() !== year
    || date.getUTCMonth() !== month - 1
    || date.getUTCDate() !== day
  ) {
    return undefined;
  }

  return date;
}
