export async function writeContentPlanningBridgeOutput(value, stream = process.stdout) {
  const output = `${JSON.stringify(value, null, 2)}\n`;
  await new Promise((resolve, reject) => {
    const onError = (error) => {
      stream.off("error", onError);
      reject(error);
    };
    stream.once("error", onError);
    stream.write(output, (error) => {
      stream.off("error", onError);
      if (error) reject(error);
      else resolve();
    });
  });
}
