# Use the Colyseus Native SDK with GDScript

The Godot client will use the official Colyseus Native SDK pinned to `godot-v0.17.11` through a narrow GDScript networking adapter. The SDK is still beta, but it implements the Colyseus 0.17 binary protocol and Schema state patches used by the server; keeping C# would require a custom bridge or a second protocol implementation, both of which create substantially more compatibility and security risk. The adapter keeps this choice replaceable if the native SDK becomes unsuitable.
