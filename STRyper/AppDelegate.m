//
//  AppDelegate.m
//  STRyper
//
//  Created by Jean Peccoud on 11/08/2014.
//  Copyright (c) 2014 Jean Peccoud. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.



#import "MainWindowController.h"

#import "FolderListController.h"
#import "PanelListController.h"
#import "SampleTableController.h"
#import "GenotypeTableController.h"
#import "DetailedViewController.h"

@implementation AppDelegate {
	
	/// The application preference window.
	__weak IBOutlet NSWindow *settingWindow;
	NSTimer *saveTimer;			/// A timer that we use to save at time intervals.
	BOOL quitWithoutCleaning;	/// whether we should terminate the application without emptying the trash.

}


UserDefaultKey ShowOffScale = @"ShowOffScale",
OutlinePeaks = @"OutlinePeaks",
ShowPeakTooltips = @"ShowPeakTooltips",
DefaultEndSize = @"DefaultEndSize",
DefaultStartSize = @"DefaultStartSize",
ReferenceStartSize = @"ReferenceStartSize",
ReferenceEndSize = @"ReferenceEndSize",
TraceRowsPerWindow = @"TraceRowsPerWindow",
TraceStackMode = @"StackMode",
PaintCrosstalkPeaks = @"PaintCrosstalkPeaks",
IgnoreCrosstalkPeaks = @"IgnoreCrossTalkPeaks",
MaintainPeakHeights = @"MaintainPeakHeights",
SynchronizeViews = @"SynchronizeViews",
SwipeBetweenMarkers = @"SwipeBetweenMarkers",
TraceTopFluoMode = @"TraceTopFluoMode",
ShowRawData = @"ShowRawData",
ShowBins = @"ShowBins",
ShowChannel0 = @"Channel0",
ShowChannel1 = @"Channel1",
ShowChannel2 = @"Channel2",
ShowChannel3 = @"Channel3",
ShowChannel4 = @"Channel4",
AddSampleInfo = @"AddSampleInfo",
AutoDetectSizeStandard = @"AutoDetectSizeStandard",
DubiousAlleleName = @"DubiousAlleleName",
MissingAlleleName = @"MissingAlleleName",
DefaultSizingOrder = @"DefaultSizingOrder",
AnnotateAdditionalPeaks = @"AnnotateAdditionalPeaks",
BottomTab = @"BottomTab",
CaseSensitiveSampleSearch = @"CaseSensitiveSampleSearch";

@synthesize managedObjectContext = _managedObjectContext, childContext = _childContext;


+ (void)initialize {

	/// We set the default settings.
	NSDictionary *defaults = @{ShowOffScale: @YES,
							   OutlinePeaks: @NO,
							   ShowPeakTooltips: @NO,
							   DefaultEndSize :@500,
							   DefaultStartSize: @0,
							   TraceRowsPerWindow: @2,
							   TraceStackMode: @0,
							   TraceTopFluoMode: @0,
							   PaintCrosstalkPeaks : @YES,
							   IgnoreCrosstalkPeaks : @NO,
							   SynchronizeViews: @YES,
							   SwipeBetweenMarkers: @YES,
							   ShowRawData: @NO,
							   MaintainPeakHeights: @YES,
							   ShowBins: @YES,
							   ShowChannel0: @YES,
							   ShowChannel1: @YES,
							   ShowChannel2: @YES,
							   ShowChannel3: @YES,
							   ShowChannel4: @YES,
							   AddSampleInfo: @NO,
							   AutoDetectSizeStandard:@NO,
							   DubiousAlleleName:@"?",
							   MissingAlleleName:@"",
							   AnnotateAdditionalPeaks:@YES,
							   DefaultSizingOrder: @2,
							   @"NSOutlineView Items sampleInspector":@[@"Sample information", @"Sizing"],
							   @"log": @NO,						
							   CaseSensitiveSampleSearch: @NO
							   
	};
	[NSUserDefaults.standardUserDefaults registerDefaults:defaults];
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if(!MOC) {
		NSLog(@"Failed to load the database.");
		abort();
	}

	/// We check the version of the persistent store to improve the detection of crosstalk in traces if necessary.
	/// Earlier versions of the app did not detect crosstalk in a way that allows showing it in trace views.
	NSURL *url = [MOC.persistentStoreCoordinator URLForPersistentStore: MOC.persistentStoreCoordinator.persistentStores.firstObject];
	if(url) {
		NSDictionary *data = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType URL:url options:nil error:nil];
		if(data) {
			NSArray *identifiers = [data valueForKey:NSStoreModelVersionIdentifiersKey];
			if(identifiers && ![identifiers containsObject:@"1.1"]) {
				NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:Chromatogram.entity.name];
				NSArray *samples = [MOC executeFetchRequest:request error:nil];
				for(Chromatogram *sample in samples) {
					[sample inferOffscaleChannel];
					for(Trace *trace in sample.traces) {
						[trace findCrossTalk];
					}
				}
			}
		}
	}
	
	/// We load the main window.
	NSWindow *mainWindow = MainWindowController.sharedController.window;
	if(!mainWindow) {
		NSLog(@"Failed to load the main window.");
		abort();
	}
	
	/// When the app quits, the trash is normally emptied. But if the app has crashed or was killed (or perhaps for other reasons), the trash may contain items.
	/// We propose to restore them		(MOVE THAT to FolderListController.m ? TO TEST)
	SampleFolder *trashFolder = FolderListController.sharedController.trashFolder;
	if(trashFolder.subfolders.count >0 || trashFolder.samples.count > 0) {
		NSAlert *alert = NSAlert.new;
		alert.messageText = @"Some deleted items were detected.";
		alert.informativeText = @"Do you wish to restore them?";
		[alert addButtonWithTitle:@"Restore Items"];
		[alert addButtonWithTitle:@"Discard Items"];
		
		[alert beginSheetModalForWindow: mainWindow completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				[self restoreTrash];
				[self.managedObjectContext.undoManager removeAllActions];
			} else {
				[FolderListController.sharedController emptyTrashWithCompletionHandler:^(NSError * error) {
					[self.managedObjectContext.undoManager removeAllActions];
				}];
			}
		}];
	}
	
	if(MOC.hasChanges) {
		[MOC save:nil];
	}
	
	[mainWindow.undoManager removeAllActions];		/// Loading the application may generate some undo actions. We remove them.
											
	saveTimer = [NSTimer timerWithTimeInterval:30 target:self selector:@selector(saveAction:) userInfo:nil repeats:NO];
	[[NSRunLoop mainRunLoop] addTimer:saveTimer forMode:NSRunLoopCommonModes];
}


/// Puts the content found in the trash folder (if not emptied) into a folder called "recovered items".
-(void)restoreTrash {
	Folder *rootFolder = FolderListController.sharedController.rootFolder;
	if(!rootFolder) {
		return;
	}
	SampleFolder *trashFolder = FolderListController.sharedController.trashFolder;
	if(trashFolder.subfolders.count > 0 || trashFolder.samples > 0) {
		SampleFolder *restored = [[SampleFolder alloc] initWithParentFolder: rootFolder];
		restored.name = @"Recovered items";
		[restored autoName];		/// to avoid duplicate names
		restored.subfolders = [trashFolder.subfolders filteredOrderedSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Folder   * _Nullable subfolder, NSDictionary<NSString *,id> * _Nullable bindings) {
			/// We don't restore smart folders
			return !subfolder.isSmartFolder;
		}]];
		restored.samples = trashFolder.samples;
	}
	[self saveAction:self];
}


/*
/// Returns the directory the application uses to store the Core Data store file.
- (NSURL *)applicationFilesDirectory
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *appSupportURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].lastObject;
	return [appSupportURL URLByAppendingPathComponent:@"jpeccoud.STRyper"];
//	return [NSURL fileURLWithPath:@"/Users/test/Documents"];
}  */


#pragma mark - preferences management/others


/// The tags attributed to controls of the newMarkerPopover, set in a nib.
enum TextFieldTag: NSInteger {
	startFieldTag = 2,
	endFieldTag = 3,
};

/// Shows the settings (preferences) window
- (IBAction)showSettings:(id)sender {
	if(!settingWindow) {
		[NSBundle.mainBundle loadNibNamed:@"Settings" owner:self topLevelObjects:nil];
		if(settingWindow.contentView) {
			NSTextField *textField = [settingWindow.contentView viewWithTag:startFieldTag];
			textField.delegate = (id)self;
			textField = [settingWindow.contentView viewWithTag:endFieldTag];
			textField.delegate = (id)self;
		}
	}
	[settingWindow makeKeyAndOrderFront:sender];
	
}



- (void)controlTextDidEndEditing:(NSNotification *)obj {
	/// We check if the values entered in the settings window for the start and end of the default visible range of traces are consistent.
	/// We change them otherwise.
	NSTextField *textField = obj.object;
	NSView *view = textField.superview;
	NSTextField *startTextField = [view viewWithTag:startFieldTag];
	NSTextField *endTextField = [view viewWithTag:endFieldTag];
	if(!startTextField || !endTextField) {
		return;
	}
	float end = endTextField.floatValue;
	float start = startTextField.floatValue;

	if(textField == startTextField) {
		if(start < 0) {
			start = 0;
		} else if(start >= end-2) {
			start = end-2;
		}
		/// As the text field is bound to the user default, we modify that directly. Changing the text field floatValue would affect the user defaults.
		[NSUserDefaults.standardUserDefaults setFloat:start forKey:DefaultStartSize];
		return;
	}
	
	if(textField == endTextField) {
		if(end < start + 2) {
			end = start+2;
		} else if(end > 1200) {
			end = 1200;
		}
		[NSUserDefaults.standardUserDefaults setFloat:end forKey:DefaultEndSize];
	}
	
}


/// This currently shows a pdf guide located in the main bundle. It would be better to use the system help
-(IBAction)showHelp:(id)sender {
	NSURL *helpFileURL = [NSBundle.mainBundle URLForResource:@"STRyper help" withExtension:@"pdf"];
	if(![NSWorkspace.sharedWorkspace openURL:helpFileURL]) {
		NSError *error = [NSError errorWithDescription:@"The help file could not be opened." suggestion:@""];
		[NSApp presentError:error];
	}
}

#pragma mark - Core Data stack

@synthesize persistentContainer = _persistentContainer;

- (NSPersistentContainer *)persistentContainer {
	/// The persistent container for the application. This implementation creates and returns a container, having loaded the store for the application to it.
	__block BOOL failure = NO;		/// indicates an error when loading the store
	__block BOOL retry = NO;		/// will be YES if we continue with a new persistent store, in case of failure.
									
	@synchronized (self) {
		if (_persistentContainer == nil) {
			_persistentContainer = [[NSPersistentContainer alloc] initWithName:@"STRyper"];
			[_persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *storeDescription, NSError *error) {
				if (error != nil) {
					failure = YES;
					/// we locate the parent folder of the store
					NSString *folder = [storeDescription.URL URLByDeletingLastPathComponent].path;
					
					NSAlert *alert = NSAlert.new;
					alert.alertStyle = NSAlertStyleCritical;
					
					if(folder) {
						NSError *fileError;
						NSFileManager *manager = NSFileManager.defaultManager;
						if(![manager isWritableFileAtPath:folder]) {
							alert.messageText = @"STRyper cannot run because it does not have writing permissions to the database folder.";
							alert.informativeText = @"You can edit the folder's permissions in the information panel of the Finder.";
							[alert addButtonWithTitle:@"Quit"];
							[alert addButtonWithTitle:@"Open Database Folder"];
							NSInteger result = [alert runModal];
							if(result != NSAlertFirstButtonReturn) {
								[NSWorkspace.sharedWorkspace selectFile:folder inFileViewerRootedAtPath:@""];
							}
							return;
						}
						NSArray *folderContent = [manager contentsOfDirectoryAtPath:folder error:&fileError];
						if(!fileError) {
							/// we will propose to continue by using a new database. We will move the existing one elsewhere.
							NSString *databasePrefix = storeDescription.URL.lastPathComponent;
							/// We extract the paths of the various files of the database
							folderContent = [folderContent filteredArrayUsingPredicate: [NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
								return [evaluatedObject rangeOfString:databasePrefix].location != NSNotFound;
							}]];
													
							alert.messageText = @"The database could not be read.";
							alert.informativeText = @"You may quit or continue with a new database. The previous one will be backed-up.";
							[alert addButtonWithTitle:@"Quit"];
							[alert addButtonWithTitle:@"Continue with New Database"];
							
							NSInteger result = [alert runModal];
							
							if(result != NSAlertFirstButtonReturn) {
								/// we prepare a backup folder, which includes the current date. We will place it in the database folder.
								NSString *backupFolder = [NSString pathWithComponents:@[folder, [NSString stringWithFormat:@"backup-%@", NSDate.date]]];
								[manager createDirectoryAtPath:backupFolder withIntermediateDirectories:YES attributes:nil error:&fileError];
								/// We move database files to this new folder.
								for(NSString *path in folderContent) {
									NSString *databaseFile = [NSString pathWithComponents:@[folder, path]];
									NSString *newLocation = [NSString pathWithComponents:@[backupFolder, path]];
									[manager moveItemAtPath:databaseFile toPath:newLocation error:&fileError];
								}
								
								NSAlert *secondAlert = NSAlert.new;
								if(!fileError) {
									secondAlert.messageText = @"The previous database was successfully backed up.";
									[secondAlert addButtonWithTitle:@"Continue"];
									[secondAlert addButtonWithTitle:@"Open Backup Folder"];
								} else {
									secondAlert.alertStyle = NSAlertStyleCritical;
									secondAlert.messageText = @"The previous database could not be backed up.";
									[secondAlert addButtonWithTitle:@"Continue"];
								}
								
								result = [secondAlert runModal];
								if(result != NSAlertFirstButtonReturn) {
									[NSWorkspace.sharedWorkspace selectFile:backupFolder inFileViewerRootedAtPath:@""];
								}
								if(!fileError) {
									retry = YES;
								}
							}
						} else {
							/// If the folder's content cannot be read, we cannot proceed
							alert.messageText = @"STRyper cannot run because the database folder cannot be read.";
							[alert addButtonWithTitle:@"Quit"];
							[alert addButtonWithTitle:@"Open Database Folder"];
							NSInteger result = [alert runModal];
							if(result != NSAlertFirstButtonReturn) {
								[NSWorkspace.sharedWorkspace selectFile:folder inFileViewerRootedAtPath:@""];
							}
						}
					} else {
						/// If the store description does not specify the URL, I don't know what to do.
						alert.messageText = @"STRyper cannot run because of an issue with its database.";
						[alert addButtonWithTitle:@"Quit"];
						[alert runModal];
					}
				}
			}];
		}
	}
	
	if(failure) {
		if(!retry) {
			[NSApp terminate:self];
			return nil;
		}
		/// If retry is YES, the problematic database was moved in the backup folder. Retrying should create a new database.
		[_persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *storeDescription, NSError *error) {
			if(error) {
				NSAlert *alert = NSAlert.new;
				alert.messageText = @"Sorry, the new database could not be created.";
				[alert addButtonWithTitle:@"Quit"];
				//[alert addButtonWithTitle:@"Report Issue"];		/// button no implemented yet. TO DO
				[alert runModal];
				abort();
			}
		}];
	}
	return _persistentContainer;
}


- (NSManagedObjectContext *)managedObjectContext {
	if (_managedObjectContext) {
		return _managedObjectContext;
	}
	
	_managedObjectContext = self.persistentContainer.viewContext;
	CDUndoManager *undoManager = CDUndoManager.new;
	_managedObjectContext.undoManager = undoManager;
	undoManager.managedObjectContext = _managedObjectContext;
	_managedObjectContext.automaticallyMergesChangesFromParent = YES;
	return _managedObjectContext;
}


- (NSManagedObjectContext *)childContext {
	if(!_childContext) {
		NSManagedObjectContext *temporaryContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
		_childContext = temporaryContext;
		_childContext.parentContext = self.managedObjectContext;
	}
	return _childContext;
}


- (NSManagedObjectContext *)newChildContext {
	NSManagedObjectContext *temporaryContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	temporaryContext.parentContext = self.managedObjectContext;
	return temporaryContext;
}


- (NSManagedObjectContext *)newChildContextOnMainQueue {
	NSManagedObjectContext *temporaryContext =[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	temporaryContext.parentContext = self.managedObjectContext;
	return temporaryContext;
}

#pragma mark - save and termination


- (IBAction)saveAction:(id)sender {
	NSManagedObjectContext *context = self.managedObjectContext;

	if (![context commitEditing]) {
		NSLog(@"%@:%@ unable to commit editing before saving", [self class], NSStringFromSelector(_cmd));
	}
	
	NSError *error = nil;
	if (context.hasChanges && ![context save:&error]) {
		NSString *log = [MainWindowController.sharedController populateErrorLogWithError:error];
		NSError *postedError = [NSError errorWithDescription:@"Sorry. The database could not be saved because of an inconsistency in the data." suggestion:@"The last action(s) will be undone to resolve the issue."];
		
		[NSApp presentError:postedError];
		[self.class recoverFromErrorInContext:context showLog:log.length > 0];
	}
	
	if(!context.hasChanges) {
		[saveTimer invalidate];
		saveTimer = [NSTimer timerWithTimeInterval:30 target:self selector:@selector(saveAction:) userInfo:nil repeats:NO];
		[[NSRunLoop mainRunLoop] addTimer:saveTimer forMode:NSRunLoopCommonModes];
	}
}


+(void)recoverFromErrorInContext:(NSManagedObjectContext *) context showLog:(BOOL)showLog {
	[context trySavingWithUndo];
	
	NSAlert *alert = NSAlert.new;
	alert.messageText = @"Recent changes have been undone to revolve the error.";
	[alert addButtonWithTitle:@"Ok"];
	if(showLog) {
		[alert addButtonWithTitle:@"Show Error Log"];
	}
	NSModalResponse returnCode = [alert runModal];
	if(returnCode == NSAlertSecondButtonReturn) {
		[MainWindowController.sharedController showErrorLogWindow:self];
	}
}

/*
- (void)applicationWillResignActive:(NSNotification *)notification {
	if(!NSApp.mainWindow.attachedSheet) {
		[self saveAction:self]; /// we save when the application becomes inactive
	}
}  */


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	/// we record the selected sample/panel folders so that can be restored at next launch.
	/// Even if we cancel termination, this isn't costly. However, they won't be restored if the app crashed and did not call this method.
	[FolderListController.sharedController recordSelectedFolder];
	[PanelListController.sharedController recordSelectedFolder];
	[SampleTableController.sharedController recordSelectedItems];
	[GenotypeTableController.sharedController recordSelectedItems];
	[MainWindowController.sharedController recordSourceController];
	[DetailedViewController.sharedController recordReferenceRange];
	
    /// Save changes in the application's managed object context before the application terminates.
	NSManagedObjectContext *context = self.managedObjectContext;
	
    if (!context) {
        return NSTerminateNow;
    }
    
    if (![context commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
        return NSTerminateCancel;
    }
    
	
    NSError *error = nil;
    if (context.hasChanges && ![context save:&error]) {
		NSString *log = [MainWindowController.sharedController populateErrorLogWithError:error];
	
        NSString *question = @"Sorry, the database could not be saved before quitting because of an inconsistency in the data. Quit anyway?";
        NSString *info = @"Quitting now will lose any changes made since the last save.";
        NSString *quitButtonTitle = @"Quit anyway";
        NSString *cancelButtonTitle = @"Cancel";
        NSAlert *alert = NSAlert.new;
        alert.messageText = question;
        alert.informativeText = info;
        [alert addButtonWithTitle:quitButtonTitle];
        [alert addButtonWithTitle:cancelButtonTitle];

        NSModalResponse answer = [alert runModal];
        
        if (answer == NSAlertSecondButtonReturn) {
			[self.class recoverFromErrorInContext:context showLog:log.length > 0];
            return NSTerminateCancel;
        }
    }
	
	if(quitWithoutCleaning) {
		return NSTerminateNow;
	}
	
	/// we delete items that are in the trash before quitting
	SampleFolder *trashFolder = FolderListController.sharedController.trashFolder;
	if(trashFolder.subfolders.count > 0 || trashFolder.samples.count > 0) {
		[FolderListController.sharedController emptyTrashWithCompletionHandler:^(NSError * error) {
			if(error) {
				self->quitWithoutCleaning = YES;
			}
			/// when have to terminate the app after the trash is emptied, because we cancel the termination (below)
			[NSApp terminate:self];
		}];
		

		/// the method above launches a block that likely finishes some time after the method has returned.
		/// We therefore cancel the termination, otherwise the app would quit in the middle of the operation
		return NSTerminateCancel;
	}
	return NSTerminateNow;
	
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
	if(sender == settingWindow) {				/// we do not close the setting window if some entered values are invalid
		[sender makeFirstResponder:nil];		/// this forces any textfield that is currently edited to validate
		if(sender.attachedSheet != nil) {
			return NO;
		}
	}
	return YES;
	
}

/*
-(void)askForQuit {
	NSAlert *alert = NSAlert.new;
	alert.messageText = @"Do you want to quit?";
	alert.informativeText = @"Any change will be save before quitting.";
	[alert addButtonWithTitle:@"Quit"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSAlertFirstButtonReturn) {
			[NSApp terminate:self];
		}
	}];
}  */






@end
