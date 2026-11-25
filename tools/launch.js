// VS Code launcher: starts tools/run.sh (the game on workspace 9) and exits when the game
// exits, so the debug session ends with it. Stopping the session stops the game.
const { spawn } = require("child_process");
const path = require("path");

const child = spawn(path.join(__dirname, "run.sh"), process.argv.slice(2), { stdio: "inherit" });
for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(sig, () => child.kill("SIGTERM"));
}
child.on("exit", (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
