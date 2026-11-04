## 1. Description
The Lift home shows your saved workouts as cards with their name, focus, exercise count, when you last did them and the muscles they work most. The one you did longest ago is marked UP NEXT. Tapping Start opens the workout with its exercises filled in. After you finish a workout, you can save it as a saved workout, and you can rename or delete saved workouts.

## 2. Where it fits
The Lift tab opens on this screen, next to the Empty workout and Custom plan tiles. Start opens the workout screen with the saved workout's exercises and targets. When that workout is finished, the saved workout's "last done" time updates, so UP NEXT moves on. After finishing any workout you can save it as a new saved workout. The server works out each card's top 3 muscles.

## 3. Data and functions
- For Server
    - GET /api/v1/templates lists your saved workouts with their exercises, last done time and top 3 muscles (worked out, not stored)
    - POST, PUT and DELETE /api/v1/templates create, change and delete a saved workout
    - Saving a workout updates the last done time of the saved workout it came from
    - The logic goes in services/
- For Client
    - Lift home lists saved workouts, marks UP NEXT and starts one with Start
    - Picking UP NEXT, the "6 days ago" text and turning a finished workout into a saved one are kept apart from the screens so they can be tested quickly
    - Data: a saved workout (name, focus, exercises with target sets, reps and rest, last done, top muscles)