## 1. Description
Two changes from testing the app on a phone. First, the rest timer gets your attention when rest is almost over, even if you put the phone down or close the app. In the last 10 seconds it beeps every second and gives a long beep at 0. While the app is open, the phone also taps in the last 10 seconds. When the app is closed or the phone is locked, notifications play the same countdown, and "Rest is over" shows at 0. Second, "Save as a workout" keeps every exercise in the workout, also the ones you didn't log, which get 3 sets and the default rest. If the workout started from a saved workout and you changed it, Finish asks "Update `name`' with your changes?" with Update, Save as new and Not now.


## 2. Where it fits
The countdown runs during the rest timer on the workout screen. The app asks for permission to send notifications once, the first time a rest timer starts. If you close the app with 10 seconds or less left, the countdown starts from the time that is left. When you open the app again, its own beeps take over. The update question shows after Finish, in place of the "Save as a workout" sheet, only for workouts started from a saved workout. Update changes that saved workout's exercises and targets and keeps its name.

## 3. Data and functions
- For Server
    - No new endpoints. Update uses PUT /api/v1/templates, which already exists
- For Client
    - The rest timer plans a "10 seconds left" notification and a "Rest is over" notification, hides them while the app is open, and replans them when the app is closed with 10 seconds or less left
    - 10 short countdown sounds (from 10 seconds down to 1), made by us, so there is no license problem
    - Notifications are marked Time Sensitive, so a Focus mode can let them through
    - Turning a finished workout into a saved workout keeps every exercise, and checks whether a workout differs from the saved workout it came from. These are kept apart from the screens so they can be tested quickly
