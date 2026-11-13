# Slow Vape for Mac

- Welcome, personal limits and a camera test lead into the dashboard. Camera access is requested when the user chooses to test or start detection. Test events are kept in memory.
- The menu bar icon opens the main window and reflects the camera and limit state. Closing the window keeps detection running. Quitting stops the camera. Opening at login and starting detection at launch are separate options.
- The two limits apply to the previous 60 minutes and the current local calendar day. The dashboard shows both remaining budgets and charts hourly, daily and weekly counts. History includes camera coverage and supports undoing the most recent event.
- A quiet warning starts at 80 percent. Crossing a limit opens a foreground panel which stays until dismissed and plays a sound at the chosen volume. An additional detection can remind after 15 minutes while a limit remains reached.
- Persist timestamps, tracking intervals and settings locally. Retain the verified detector and package the app with the existing camera-only sandbox entitlement.
- Use a native SwiftUI app with a compact sidebar, a graphite palette and green for active tracking. Use amber for warnings and red for the interrupting panel. AppKit manages the menu bar and the alert window.
