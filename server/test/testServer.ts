import { ColyseusTestServer, boot } from "@colyseus/testing";

import appConfig from "../src/app.config.js";

let serverPromise: Promise<ColyseusTestServer<typeof appConfig>> | undefined;

export function getTestServer(): Promise<ColyseusTestServer<typeof appConfig>> {
  if (!serverPromise) {
    serverPromise = boot(appConfig);
  }

  return serverPromise;
}

after(async () => {
  if (!serverPromise) {
    return;
  }

  const server = await serverPromise;
  await server.cleanup();
  await new Promise((resolve) => setTimeout(resolve, 50));
  await server.shutdown();
});
