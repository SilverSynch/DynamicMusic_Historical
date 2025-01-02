This was a modification to an existing mod project, meant to add new functionalities that had not existed in the project at the time, for personal use.

The intended purpose of DynamicMusic is to identify the player scenario within the game Morrowind, and change to music track to an appropriate one as determined by database files ("soundbanks") that contained scenario triggers and the appropriate tracks.
The project is similar to another mod for Morrowind, MUSE2, however, MUSE2 is exclusive to the Morrowind Script Extender, and DynamicMusic is written for OpenMorrowind. Since these two enviroments have very different APIs, code could not be shared between these two projects.

The modifications reimpement two features that existed in MUSE2, but not DynamicMusic, at the time:
* Enemy-based music lists. The system listens for enemies in combat, and finds soundbanks which list those enemies as their specific trigger.
* Tileset-based music lists. The system listens for objects loaded nearby the player, and finds soundbanks which list those objects as their specific trigger.

This modification was meant to be used with a companion script, which automatically translates MUSE2 soundbanks to DynamicMusic soundbanks, including the new trigger types added by me. This script is included for completeness.

Since making these modifications, the original project was completely rewritten by its original author, and has implemented their own enemy trigger method.
