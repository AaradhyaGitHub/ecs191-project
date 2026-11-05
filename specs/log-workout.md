## 1. Description 
You start a workout, add exercises, and log each set: weight, reps, rest and how hard it was. The screen shows what's next and what's done. When you tap Finish, the workout is saved to the server, so it counts toward your muscle map and your exercise history.

## 2. What the user does and sees
The workout screen opens after you pick exercises for an empty workout, or when you start a saved workout. From it you can add more exercises with the picker and log sets in the set entry sheet. The workout stays on the phone until you tap Finish, then it's sent to the server once. Saved workouts feed "Your exercises", the Home history and muscle map, and Goals.

## 3. Data and functions
- For Server
    - POST /api/v1/workouts saves a finished workout and its sets once. Sending it again changes nothing
    - Saving also updates your history for each exercise (last set, times done, last done)
    - GET /api/v1/workouts and GET /api/v1/workouts/{id} list your workouts and show one
    - GET and PUT /api/v1/users/me read and change your units and body weight
    - The logic goes in services/
- For Client
    - The active workout is stored on the phone until Finish, and is sent again if the first try fails
    - Up next, supersets, the rest timer, plates and lb/kg are kept apart from the screens so they can be tested quickly
    - Data: a workout (name, start, end, saved workout it came from) and its sets (exercise, order, type, weight, reps or seconds, effort, rest, superset group)