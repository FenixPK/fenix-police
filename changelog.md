# Fenix Police Response

**1.0.1**
- Hopefully fix bug with some cops being unarmed. They had weapons but were still using fists. I've added a loop to check if they are armed with the weapon I just tried to set using GiveWeaponToPed and it will retry a few times before giving up. This can still lead to unarmed officers but it seems it will continue to fail forever otherwise. It is better than before. 
- Added config option Config.PoliceWantedProtection to protect players that are employed as police from being wanted. Also option Config.PlayerPoliceOnlyOnDuty to only count them as police if on-duty. Will prevent my ApplyWantedLevel and SetWantedLevel functions from doing anything to players considered police. And also because the base game will still do what it does regarding wanted stars this will check if a player is considered a police officer every cycle and if they have a wanted level it clears it. I HAVE NOT TESTED THIS because I don't have anyone with a police job on my server.


**1.0.0**
- Initial Release