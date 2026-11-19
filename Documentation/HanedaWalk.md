# Run the Haneda walk

Double-click `Scripts/start-haneda-walk.command` in Finder. The launcher starts both local drivers, builds AirBorder, and opens **AirBorder Haneda Walk**, a dedicated iPhone simulator. The first build takes longer; later launches reuse the build directory. Keep the launcher window open while using the app.

You need a Mac with Xcode and an installed iOS simulator runtime, plus Python 3. The published Haneda map image needs an internet connection when it is first loaded. No API key, paid service, or AI model is required.

## Controls

Type a number in the launcher window and press Return:

| Control | Effect |
| --- | --- |
| 1 | Walk continuously along the current route |
| 2 | Pause at the current position |
| 3 | Advance to the next recorded position |
| 4 | Change the flight's assigned gate to 108A |
| 5 | Change the assigned gate back to 105 |
| 6 | Close the junction passage |
| 7 | Reopen the passage |
| 8 | Reset the driver to the beginning and restore Gate 105 |
| 9 | Show the current gate, progress and whether walking is paused |
| Q | Stop both drivers and close the launcher |

Switch between **Map** and **Camera** in the iPhone app. Both use the same position and heading. After choosing Gate 108A in the launcher, tap **View route** in the app's gate-change alert. The route changes from the passenger's current position; the Camera view turns with the driver heading. For a repeat walkthrough, use 8, then 1. The app remains installed after quitting; start the launcher again to reconnect its drivers.

The driver supplies time-stamped position, floor and heading readings, while a second driver supplies flight changes. The app polls those inputs and updates the moving map and RealityKit scene. Movement is continuous between recorded coordinates, with intentional pauses at readings that need floor confirmation. This is a local simulation, not positioning from the Mac or iPhone's physical location. The scene uses Haneda's published map and referenced terminal features, with illustrative interior geometry described in [the scene sources](HanedaSceneReferences.md).

## Troubleshooting

- If the app is stationary, use 1 and check 9. A deliberately unconfirmed floor must be confirmed before route progression; 3 advances the driver to the next reading.
- To start from scratch, quit and double-click the launcher again. It resets only this dedicated simulator's AirBorder state.
- If setup fails, the launcher prints the exact log folder under `~/Library/Logs/AirBorder Walk/`. It stops only the driver processes it started.
- If the map image cannot load, restore the Mac's internet connection and relaunch. The position driver itself runs locally.
- If the launcher says the Simulator desktop app is missing, this Xcode installation only has the simulator tools. AirBorder and the drivers can run for automated tests and recordings, but interacting with an iPhone window requires the full Xcode app. The launcher reports this instead of closing the drivers.

For a command-line launch, run `python3 Scripts/haneda-walk.py`. For driver-only verification, run `python3 Scripts/haneda-walk.py --check-drivers`. Advanced options include `--device`, `--derived-data` and `--skip-build`; ordinary use does not require them.
