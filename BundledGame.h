#pragma once
#import <UIKit/UIKit.h>

// YES when this build carries the bundled game (game/Minecraft-1.0.jar inside the app bundle).
BOOL BundledGame_isPresent(void);

// Root screen used instead of the launcher UI. Installs the bundled game, makes sure an offline
// account and profile exist, requests JIT the same way the stock Play button does, then starts the
// game directly.
@interface BundledGameBootViewController : UIViewController
@end
