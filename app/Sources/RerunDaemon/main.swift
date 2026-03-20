import RerunCore
import Foundation

print("Rerun daemon v\(Rerun.version) starting...")
print("Press Ctrl+C to stop.")

// Keep the daemon alive
RunLoop.main.run()
