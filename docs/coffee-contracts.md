# Coffee contracts

Each coffee changes how much app access the user gives up. These contracts are intentionally fixed while the prototype is being validated.

| Coffee | Duration | Selection | Restriction behavior |
| --- | ---: | --- | --- |
| Latte | 25 min | None | Timer only; all apps remain available |
| Cappuccino | 30 min | 1–4 blocked apps | Only selected distractions are hidden when running or activated |
| Americano | 45 min | 1–8 allowed apps | Regular apps outside the selection are hidden |
| Espresso | 30 min | 1–4 allowed apps | Regular apps outside the tighter selection are hidden |

All hiding is cooperative and reversible. Pausing lifts the applicable restriction; resuming reapplies it. Aborting, completing, or recovering an expired session restores only apps BrewFocus recorded as having hidden.

The contracts do not imply control over websites, notifications, background processes, or system Focus. Custom durations and custom recipes remain outside the current scope.
