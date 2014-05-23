//
//  AppDelegate.m
//  Vagrant Bar
//
//  Created by Paul on 22/05/2014.
//  Copyright (c) 2014 BipSync. All rights reserved.
//

#import "AppDelegate.h"
#import <fcntl.h>


@implementation AppDelegate


- (void) applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    if ( ![self detectVagrantPath] ) {
        
        NSAlert * alert = [NSAlert alertWithMessageText:@"Vagrant Bar" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Error: Unable to detect path to vagrant\n\nInstall from: http://www.vagrantup.com/\n"];
        [alert runModal];
        
        [[NSApplication sharedApplication] terminate:self];
        return;
        
    }
    
    [self setupStatusBarItem];
    [self setupMachineSubmenu];
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    
}

- (void) setupStatusBarItem {
    
    NSMenu * menu = [[NSMenu alloc] init];
    menu.delegate = self;
    
    NSStatusBar * bar = [NSStatusBar systemStatusBar];
    NSStatusItem * item = [bar statusItemWithLength:NSVariableStatusItemLength];
    item.highlightMode = YES;
    item.menu = menu;
    item.image = [NSImage imageNamed:@"menubar"];
    item.toolTip = [NSString stringWithFormat:@"Vagrant Bar v%@",
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    
    self.statusItem = item;
    self.mainMenu = menu;

}

- (void) setupMachineSubmenu {
    
    machineSubmenu = [[NSMenu alloc] init];
    machineSubmenu.autoenablesItems = NO;
    [self addMenuItem:@"Halt" withImage:NSImageNameStopProgressTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Provision" withImage:NSImageNameActionTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Reload" withImage:NSImageNameRefreshTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Resume" withImage:NSImageNameLockUnlockedTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Suspend" withImage:NSImageNameLockLockedTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Up" withImage:NSImageNameGoRightTemplate toMenu:machineSubmenu];
    
}

- (void) applicationWillTerminate:(NSNotification *)notification {
    
    self.statusItem = nil;
    
}

- (void) quit {
    
    [[NSApplication sharedApplication] terminate:self];
    
}

- (void) menuWillOpen:(NSMenu *)menu {
    
    if ( menu != self.mainMenu ) {
        return;
    }
    
    [menu removeAllItems];
    [menu addItemWithTitle:@"Fetching machine status.." action:nil keyEquivalent:@""];
    [self appendCommonMenuItems:menu];
    
    [self performSelectorInBackground:@selector(runGlobalStatus) withObject:nil];
    
}

- (void) appendCommonMenuItems:(NSMenu *)menu {
    
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Vagrant Bar" action:@selector(quit) keyEquivalent:@""];
    
}

- (void) runGlobalStatus {
    
    if ( runningGlobalStatus ) {
        return;
    }
    runningGlobalStatus = YES;
    
    NSTask * task = [self runCommandWithArguments:@[ @"global-status", @"--prune" ]];
    
    NSFileHandle * fileOutput = [task.standardOutput fileHandleForReading];
    NSData * dataOutput = [fileOutput readDataToEndOfFile];
    NSString * stringOutput = [[NSString alloc] initWithData:dataOutput encoding:NSUTF8StringEncoding];
    
    NSMutableArray * machineItems = [@[] mutableCopy];
    
    NSArray * machineStatuses = [self parseGlobalStatus:stringOutput];
    for ( NSDictionary * machineStatus in machineStatuses ) {
        
        NSString * title = [NSString stringWithFormat:@"%@ (%@): %@",
                            machineStatus[ @"name" ],
                            machineStatus[ @"id" ],
                            machineStatus[ @"state" ]
                            ];
        NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:title action:@selector(machineAction:) keyEquivalent:@""];
        
        
        if ( !machineIds ) {
            machineIds = [@[] mutableCopy];
        }
        [machineIds addObject:machineStatus[ @"id" ]];
        
        item.tag = [machineIds count] - 1;
        item.submenu = [machineSubmenu copy];
        
        BOOL running = [machineStatus[ @"state" ] isEqualToString:@"running"],
        suspended = [machineStatus[ @"state" ] isEqualToString:@"suspended"],
        stopped = [machineStatus[ @"state" ] isEqualToString:@"stopped"];
        
        [[item.submenu itemAtIndex:0] setEnabled:!stopped]; // halt
        [[item.submenu itemAtIndex:1] setEnabled:YES]; // provision
        [[item.submenu itemAtIndex:2] setEnabled:YES]; // reload
        [[item.submenu itemAtIndex:3] setEnabled:suspended]; // resume
        [[item.submenu itemAtIndex:4] setEnabled:running]; // suspend
        [[item.submenu itemAtIndex:5] setEnabled:!running]; //up
        
        [machineItems addObject:item];
        
    }
    
    [self.mainMenu removeAllItems];
    if ( [machineItems count] ) {
        NSMenuItem * allItem = [[NSMenuItem alloc] initWithTitle:@"All Machines" action:@selector(allAction:) keyEquivalent:@""];
        allItem.submenu = [machineSubmenu copy];
        allItem.tag = -1;
        [self.mainMenu addItem:allItem];
        [self.mainMenu addItem:[NSMenuItem separatorItem]];
        for ( NSMenuItem * machineItem in machineItems ) {
            [self.mainMenu addItem:machineItem];
        }
    }
    else {
        NSMenuItem * noItem = [[NSMenuItem alloc] initWithTitle:@"No machines registered" action:@selector(allAction:) keyEquivalent:@""];
        [noItem setEnabled:NO];
        [self.mainMenu addItem:noItem];
    }
    [self appendCommonMenuItems:self.mainMenu];
    
    runningGlobalStatus = NO;
    
}

- (void) allAction:(id)sender {
    
}

- (void) machineAction:(id)sender {
    
}

- (void) machineHalt:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"halt" withMachine:machineId];
    
}

- (void) machineProvision:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"provision" withMachine:machineId];
    
}

- (void) machineReload:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"reload" withMachine:machineId];
    
}

- (void) machineResume:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"resume" withMachine:machineId];
    
}

- (void) machineSuspend:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"suspend" withMachine:machineId];
    
}

- (void) machineUp:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"up" withMachine:machineId];
    
}

- (NSString *) machineIdFromSender:(id)sender {
    
    if ( ![sender isKindOfClass:[NSMenuItem class]] ) {
        return nil;
    }
    NSMenuItem * item = sender;
    if ( !item.parentItem ) {
        return nil;
    }
    long index = item.parentItem.tag;
    if ( index < 0 || index > [machineIds count] - 1 ) {
        return nil;
    }
    return [machineIds objectAtIndex:index];
    
}

- (void) runCommand:(NSString *)command withMachine:(NSString *)machineId {
    
    if ( machineId ) {
        [self runCommandWithArguments:@[ command, machineId ]];
    }
    else {
        for ( NSString * otherMachineId in machineIds ) {
            [self runCommandWithArguments:@[ command, otherMachineId ]];
        }
    }
    
}

- (NSTask *) runCommandWithArguments:(NSArray *)arguments {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = vagrantPath;
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    [task launch];
    
    return task;
    
}

- (void) runBackgroundCommand:(NSString *)command withMachine:(NSString *)machineId {
    
    if ( machineId ) {
        [self runBackgroundCommandWithArguments:@[ command, machineId ]];
    }
    else {
        for ( NSString * otherMachineId in machineIds ) {
            [self runBackgroundCommandWithArguments:@[ command, otherMachineId ]];
        }
    }
    
}

- (NSTask *) runBackgroundCommandWithArguments:(NSArray *)arguments {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = vagrantPath;
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    
    NSString * askPassPath = [[NSBundle mainBundle] pathForResource:@"AskPass" ofType:@""];
    
    NSMutableDictionary * environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [environment setValue:@"NONE" forKey:@"DISPLAY"];
    [environment setValue:askPassPath forKey:@"SUDO_ASKPASS"];
    task.environment = environment;
    
    NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
    
    NSFileHandle * readOutput = [task.standardOutput fileHandleForReading];
    [notificationCenter addObserver:self
                           selector:@selector(outputReadNotification:)
                               name:NSFileHandleReadCompletionNotification
                             object:readOutput];
    
    [task launch];
    
    [readOutput readInBackgroundAndNotify];
    
    return task;
    
}

- (void) addMenuItem:(NSString *)title withImage:(NSString *)imageName toMenu:(NSMenu *)menu {
    
    NSMenuItem * item =
    [menu addItemWithTitle:[NSString stringWithFormat:@" %@", title]
                    action:NSSelectorFromString( [NSString stringWithFormat:@"machine%@:", title] ) keyEquivalent:@""];
    
    item.image = [NSImage imageNamed:imageName];
    item.image.size = NSSizeFromString(@"{11,12}");
    
}

- (void) outputReadNotification:(NSNotification *)notification {
    
    NSData * data = [notification.userInfo objectForKey:NSFileHandleNotificationDataItem];
    NSString * string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if ( ![string length] ) {
        return;
    }
    
    NSUserNotification * userNotification = [[NSUserNotification alloc] init];
    userNotification.title = @"Vagrant Bar";
    if ( [string length] > 4 && [[string substringToIndex:4] isEqualToString:@"==> "] ) {
        string = [string substringFromIndex:4];
    }
    userNotification.informativeText = string;
    userNotification.soundName = NSUserNotificationDefaultSoundName;
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
    
    //
    
    NSFileHandle * readOutput = notification.object;
    [readOutput readInBackgroundAndNotify];
    
}

- (BOOL) userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    
    return YES;
    
}

- (NSArray *) parseGlobalStatus:(NSString *)stringOutput {
    
    NSMutableArray * status = [@[] mutableCopy];
    
    NSArray * lines = [stringOutput componentsSeparatedByString:@"\n"];
    BOOL listingMachines = NO;
    for ( NSString * line in lines ) {
        if ( [line length] > 4 && [[line substringToIndex:5] isEqualToString:@"-----"] ) {
            listingMachines = YES;
            continue;
        }
        if ( listingMachines ) {
            NSArray * tokens = [line componentsSeparatedByString:@" "];
            NSMutableArray * validTokens = [@[] mutableCopy];
            for ( NSString * token in tokens ) {
                if ( [[token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0 ) {
                    [validTokens addObject:token];
                }
            }
            if ( [validTokens count] == 5 ) {
                
                [status addObject:@{
                                    @"id" : validTokens[ 0 ],
                                    @"name" : validTokens[ 1 ],
                                    @"provider" : validTokens[ 2 ],
                                    @"state" : validTokens[ 3 ],
                                    @"path" : validTokens[ 4 ]
                                    }];
                
            }
            else {
                break;
            }
        }
    }
    return status;
    
}

- (BOOL) detectVagrantPath {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[ @"-c", @"which vagrant" ];
    task.standardOutput = [NSPipe pipe];
    [task launch];
    
    NSFileHandle * output = [task.standardOutput fileHandleForReading];
    NSData * data = [output readDataToEndOfFile];
    if ( ![data length] ) {
        return NO;
    }
    NSString * string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    vagrantPath = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    return YES;
    
}


@end