#import "BundledGame.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "authenticator/BaseAuthenticator.h"
#import "ios_uikit_bridge.h"
#import "LauncherPreferences.h"
#import "MinecraftResourceUtils.h"
#import "PLProfiles.h"
#import "utils.h"

// Standalone "Minecraft 1.0" boot path for Amethyst-iOS.
//
// Instead of showing the launcher UI, the app takes the Minecraft 1.0 jar (bundled in the app as
// game/Minecraft-1.0.jar, or picked by the player on first launch and kept in the app's Documents folder),
// installs it, creates an offline account and a profile, requests JIT the same way the stock Play button does
// (StikDebug / TrollStore / SideStore), and starts the game through the same call the Play button uses
// (UIKit_launchMinecraftSurfaceVC).

static NSString *const kGameId = @"1.0";
static NSString *const kProfileName = @"Minecraft 1.0";
static NSString *const kDefaultPlayerName = @"Player";

static NSString *UserJarPath(void) {
    return [NSString stringWithFormat:@"%s/Minecraft-1.0.jar", getenv("POJAV_HOME")];
}

// The game file is either bundled in the app or supplied by the player (kept in Documents, visible in Files).
static NSString *GameJarPath(void) {
    NSString *bundled = [NSBundle.mainBundle pathForResource:@"Minecraft-1.0" ofType:@"jar" inDirectory:@"game"];
    if (bundled != nil) {
        return bundled;
    }
    NSString *user = UserJarPath();
    return [NSFileManager.defaultManager fileExistsAtPath:user] ? user : nil;
}

BOOL BundledGame_isPresent(void) {
    // This build always boots straight into the game. If the jar is missing, the boot screen asks for it.
    return YES;
}

static NSError *BundledError(NSString *message) {
    return [NSError errorWithDomain:@"BundledGame" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// A jar is a zip file: it starts with "PK\x03\x04".
static BOOL LooksLikeJar(NSString *path) {
    unsigned long long size = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileSize];
    if (size < 1024) {
        return NO;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:4];
    [handle closeFile];
    return head.length == 4 && memcmp(head.bytes, "PK\x03\x04", 4) == 0;
}

// Minecraft 1.0 user names: letters, digits and underscore, at most 16 characters.
static NSString *SanitizedPlayerName(NSString *raw) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < raw.length && out.length < 16; i++) {
        unichar c = [raw characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [out appendFormat:@"%C", c];
        }
    }
    return out.length > 0 ? [out copy] : kDefaultPlayerName;
}

static NSString *PlayerNameFilePath(void) {
    return [NSString stringWithFormat:@"%s/bundled_player_name.txt", getenv("POJAV_HOME")];
}

static NSString *SavedPlayerName(void) {
    NSString *name = [NSString stringWithContentsOfFile:PlayerNameFilePath() encoding:NSUTF8StringEncoding error:nil];
    return name.length > 0 ? SanitizedPlayerName(name) : nil;
}

static void SavePlayerName(NSString *name) {
    [name writeToFile:PlayerNameFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Copies the jar into <game dir>/versions/1.0/ and writes the matching version file.
// Safe to run on every launch; it only rewrites the jar when its size differs.
static NSError *InstallGame(void) {
    NSString *source = GameJarPath();
    const char *gameDirC = getenv("POJAV_GAME_DIR");
    if (source == nil) {
        return BundledError(@"The game file (Minecraft-1.0.jar) was not found.");
    }
    if (gameDirC == NULL) {
        return BundledError(@"The game folder is not set up yet (POJAV_GAME_DIR is empty).");
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *versionDir = [NSString stringWithFormat:@"%s/versions/%@", gameDirC, kGameId];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:versionDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        return error;
    }

    NSString *target = [versionDir stringByAppendingPathComponent:[kGameId stringByAppendingString:@".jar"]];
    unsigned long long sourceSize = [[fm attributesOfItemAtPath:source error:nil] fileSize];
    unsigned long long targetSize = [[fm attributesOfItemAtPath:target error:nil] fileSize];
    if (![fm fileExistsAtPath:target] || sourceSize != targetSize) {
        [fm removeItemAtPath:target error:nil];
        if (![fm copyItemAtPath:source toPath:target error:&error]) {
            return error;
        }
    }

    NSDictionary *versionJson = @{
        @"id": kGameId,
        @"type": @"release",
        @"time": @"2011-11-18T00:00:00+00:00",
        @"releaseTime": @"2011-11-18T00:00:00+00:00",
        @"minimumLauncherVersion": @4,
        @"mainClass": @"net.minecraft.client.Minecraft",
        @"minecraftArguments": @"${auth_player_name} ${auth_session}",
        @"libraries": @[],
        @"javaVersion": @{@"component": @"jre-legacy", @"majorVersion": @8}
    };
    NSString *jsonPath = [versionDir stringByAppendingPathComponent:[kGameId stringByAppendingString:@".json"]];
    return saveJSONToFile(versionJson, jsonPath);
}

// Creates (or refreshes) the offline account and makes it the current one.
static BOOL EnsureOfflineAccount(NSString *name) {
    NSString *accountsDir = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    [NSFileManager.defaultManager createDirectoryAtPath:accountsDir withIntermediateDirectories:YES attributes:nil error:nil];
    LocalAuthenticator *auth = [[LocalAuthenticator alloc] initWithInput:name];
    __block BOOL saved = NO;
    [auth loginWithCallback:^(id status, BOOL success) {
        saved = success;
    }];
    return saved && BaseAuthenticator.current != nil;
}

// Creates the "Minecraft 1.0" profile and selects it. Old Minecraft versions need fixed-function OpenGL,
// so pin the gl4es renderer explicitly.
static void EnsureProfile(void) {
    PLProfiles *profiles = PLProfiles.current;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = kProfileName;
    entry[@"lastVersionId"] = kGameId;
    entry[@"renderer"] = @RENDERER_NAME_GL4ES;
    [[profiles profiles] setObject:entry forKey:kProfileName];
    [profiles setSelectedProfileName:kProfileName];
}

// Same JIT request the stock launcher makes in LauncherNavigationController invokeAfterJITEnabled:.
static void RequestJIT(void) {
    BOOL hasTrollStoreJIT = getEntitlementValue(@"jb.pmap_cs.custom_trust");
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier;
    NSURL *url = nil;

    if (hasTrollStoreJIT) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", bundleId]];
    } else if (@available(iOS 17.4, *)) {
        NSString *scriptDataString = @"";
        if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        url = [NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", bundleId, getpid(), scriptDataString]];
    } else {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]];
    }
    if (url != nil) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

@interface BundledGameBootViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *chooseButton;
@property (nonatomic, assign) BOOL started;
@end

@implementation BundledGameBootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:17];
    label.text = @"Minecraft 1.0";
    [self.view addSubview:label];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"Choose Minecraft-1.0.jar" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(chooseJar) forControlEvents:UIControlEventTouchUpInside];
    button.hidden = YES;
    [self.view addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [button.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:24],
        [button.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
    self.statusLabel = label;
    self.chooseButton = button;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) {
        return;
    }
    self.started = YES;
    [self beginFlow];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = [@"Minecraft 1.0\n\n" stringByAppendingString:text];
}

- (void)beginFlow {
    self.chooseButton.hidden = YES;
    if (GameJarPath() == nil) {
        [self setStatus:@"Minecraft 1.0 needs your game file, Minecraft-1.0.jar.\n\nTap the button and pick it from the Files app (iCloud Drive, On My iPhone, Downloads...). You only have to do this once."];
        self.chooseButton.hidden = NO;
        return;
    }
    [self askForNameIfNeeded];
}

- (void)chooseJar {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *picked = urls.firstObject;
    if (picked == nil) {
        return;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dest = UserJarPath();
    [fm removeItemAtPath:dest error:nil];
    NSError *error = nil;
    if (![fm copyItemAtURL:picked toURL:[NSURL fileURLWithPath:dest] error:&error]) {
        [self setStatus:[NSString stringWithFormat:@"Could not copy that file:\n%@", error.localizedDescription]];
        self.chooseButton.hidden = NO;
        return;
    }
    if (!LooksLikeJar(dest)) {
        [fm removeItemAtPath:dest error:nil];
        [self setStatus:@"That does not look like Minecraft-1.0.jar. Pick the game's jar file."];
        self.chooseButton.hidden = NO;
        return;
    }
    [self beginFlow];
}

// First launch: ask for a player name (servers do not allow two players with the same name).
- (void)askForNameIfNeeded {
    NSString *saved = SavedPlayerName();
    if (saved != nil) {
        [self prepareWithName:saved];
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Player name"
        message:@"Pick the name you want to use in multiplayer. Every player on a server needs a different one."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = kDefaultPlayerName;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController *weakAlert = alert;
    __weak BundledGameBootViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Play" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = SanitizedPlayerName(weakAlert.textFields.firstObject.text);
        SavePlayerName(name);
        [weakSelf prepareWithName:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)prepareWithName:(NSString *)name {
    [self setStatus:@"Preparing game files..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *installError = InstallGame();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (installError != nil) {
                [self setStatus:[NSString stringWithFormat:@"Could not install the game:\n%@", installError.localizedDescription]];
                return;
            }
            if (!EnsureOfflineAccount(name)) {
                [self setStatus:@"Could not create the offline account."];
                return;
            }
            EnsureProfile();

            NSString *jsonPath = [NSString stringWithFormat:@"%s/versions/%@/%@.json", getenv("POJAV_GAME_DIR"), kGameId, kGameId];
            NSMutableDictionary *metadata = parseJSONFromFile(jsonPath);
            if (metadata == nil || metadata[@"NSErrorObject"] != nil) {
                [self setStatus:@"Could not read the game's version file."];
                return;
            }
            [MinecraftResourceUtils tweakVersionJson:metadata];
            [self enableJITThenLaunchWithMetadata:metadata];
        });
    });
}

// The Java runtime needs JIT. If it is already on, start right away; otherwise request it the same way the
// stock launcher does (this hops to StikDebug and back) and wait here until it is enabled.
- (void)enableJITThenLaunchWithMetadata:(NSDictionary *)metadata {
    if (isJITEnabled(NO)) {
        UIKit_launchMinecraftSurfaceVC(self.view.window, metadata);
        return;
    }

    [self setStatus:@"Waiting for JIT...\n\nStikDebug should open. Allow it, then come back here. The game starts by itself as soon as JIT is on."];
    RequestJIT();

    __weak BundledGameBootViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!isJITEnabled(NO)) {
            usleep(1000 * 200);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            BundledGameBootViewController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                UIKit_launchMinecraftSurfaceVC(strongSelf.view.window, metadata);
            }
        });
    });
}

@end
