//
//  FolderListController.m
//  STRyper
//
//  Created by Jean Peccoud on 07/08/2022.
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



#import "FolderListController.h"
#import "SampleTableController.h"
#import "FileImporter.h"
#import "ProgressWindow.h"
#import "SmartFolder.h"
#import "Chromatogram.h"
#import "SampleSearchHelper.h"
#import "MainWindowController.h"
#import "HoveredTableRowView.h"
#import "GenotypeTableController.h"


@interface FolderListController ()

/// redefinition of readonly properties as readwrite
@property (nonatomic) SampleFolder *smartFolderContainer;
@property (nonatomic) BOOL canImportSamples;

@end


@implementation FolderListController {
	/// ivars used when import ing ABIF files being dragged from the finder to a folder,
	/// The avoid extracting path of ABIF files at each step of the dragging sequence
	NSArray *draggedABIFFilePaths;       		/// paths of ABIF files being dragged
	NSInteger lastDraggingSequence;				/// will contain the identifier of the last dragging sequence (to avoid retrieving the files paths several times for the same sequence)
	NSProgress *exportProgress;					/// to monitor the progress of folder export
	NSUInteger totalSamplesToProcess;
	NSUInteger totalSamplesProcessed;
}


/// We use a this trash folder to avoid a delay that would occur when deleting folders containing thousands of samples, or many samples.
/// The trash is emptied only upon quitting.
/// This folder has the advantage of allowing restoring the trash if the app crashed before the user could undo a deletion.

@synthesize smartFolderContainer = _smartFolderContainer, trashFolder = _trashFolder;


+ (instancetype)sharedController {
	static FolderListController *controller = nil;
	static dispatch_once_t once;
	
	dispatch_once(&once, ^{
		controller = self.new;
	});
	return controller;
}


- (NSNibName)nibName {
	return @"LeftPane";
}


- (void)viewDidLoad {
	
	[super viewDidLoad];
	
	/// to drag folders between folders, samples between folders and import samples into folders from ABIF files
	[outlineView registerForDraggedTypes:@[FolderDragType, ChromatogramObjectIDPasteboardType, NSPasteboardTypeFileURL]];
}


- (NSString *)entityName {
	return SampleFolder.entity.name;
}


- (__kindof Folder *)trashFolder {
	if(!_trashFolder) {
		NSString *uri = [NSUserDefaults.standardUserDefaults stringForKey:[@"trash" stringByAppendingString:self.entityName]];
		_trashFolder = [self.managedObjectContext objectForURIString:uri expectedClass:Folder.class];
	}
	return _trashFolder;
}


- (SampleFolder *)smartFolderContainer {
	if(!_smartFolderContainer) {
		NSString *uri = [NSUserDefaults.standardUserDefaults stringForKey:@"smartFolderContainer"];
		_smartFolderContainer = [self.managedObjectContext objectForURIString:uri expectedClass:Folder.class];
	}
	return _smartFolderContainer;
}


- (void)configureTableContent {
	[super configureTableContent];
	NSManagedObjectContext *MOC = self.managedObjectContext;
	NSString *entityName = self.entityName;
	if(!self.trashFolder) {
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
		request.predicate = [NSPredicate predicateWithFormat:@"parent == nil && name == %@", @"Trash"];
		NSArray *trashFolders = [MOC executeFetchRequest:request error:nil];
		
		if(trashFolders.count > 1) {
			/// this should not happen, as the UI does not allow creating root folders.
			NSLog(@"several trash folders found for %@!", entityName);
		}
		
		_trashFolder = trashFolders.firstObject;
		
		if(!_trashFolder) {
			_trashFolder = [NSEntityDescription insertNewObjectForEntityForName:self.entityName inManagedObjectContext:MOC];
			_trashFolder.name = @"Trash";
			/// we save a reference of the trash folder in the user defaults to be able to retrieve it
			[_trashFolder.managedObjectContext obtainPermanentIDsForObjects:@[_trashFolder] error:nil];
		}
		[NSUserDefaults.standardUserDefaults setObject: _trashFolder.objectID.URIRepresentation.absoluteString
												forKey:[@"trash" stringByAppendingString:self.entityName]];

	}
	
	if(!self.smartFolderContainer) {
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
		request.predicate = [NSPredicate predicateWithFormat:@"parent == nil && name == %@", @"__smartFolderContainer"];
		NSArray *smartFolderContainers = [MOC executeFetchRequest:request error:nil];
		
		if(smartFolderContainers.count > 1) {
			/// this should not happen, as the UI does not allow creating root folders. But we manage this situation anyway.
			NSLog(@"several smart folder containers found for %@!", entityName);
		}
		
		_smartFolderContainer = smartFolderContainers.firstObject;
		
		if(!_smartFolderContainer) {
			_smartFolderContainer = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:MOC];
			_smartFolderContainer.name = @"__smartFolderContainer";
			/// we save a reference of the trash folder in the user defaults to be able to retrieve it
			[_smartFolderContainer.managedObjectContext obtainPermanentIDsForObjects:@[_smartFolderContainer] error:nil];
		}
		
		[NSUserDefaults.standardUserDefaults setObject: _smartFolderContainer.objectID.URIRepresentation.absoluteString
												forKey:@"smartFolderContainer"];
		
		for(SampleFolder *folder in self.rootFolder.subfolders) {
			if(folder.isSmartFolder) {
				folder.parent = self.smartFolderContainer;
			}
		}
	}
}


-(void)setSelectedFolder:(Folder *)selectedFolder {

	_selectedFolder = selectedFolder;
	self.canImportSamples = selectedFolder != nil && !selectedFolder.isSmartFolder && selectedFolder != self.rootFolder && selectedFolder != self.trashFolder;
	
	
}


- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
	
	Folder *folder = [self _folderForItem:item];
	if(folder == self.smartFolderContainer || folder == self.rootFolder) {
		/// these "section" folders have special row views
		HoveredTableRowView *rowView = [outlineView makeViewWithIdentifier:@"groupRowView" owner:self];
		if(!rowView) {
			rowView = HoveredTableRowView.new;
			NSButton *button = [NSButton buttonWithImage:[NSImage imageNamed:@"addCircleStroke"] target:nil action:nil];
			button.bezelStyle = NSBezelStyleRecessed;
			button.bordered = NO;
			button.showsBorderOnlyWhileMouseInside = YES;
			button.imagePosition = NSImageOnly;
			button.imageScaling = NSImageScaleNone;
			rowView.hoveredButton = button;
			rowView.hoveredButton.target = self;
			rowView.hoveredButton.action = @selector(addFolder:);
			rowView.identifier = @"groupRowView";
		}
		if(folder == self.smartFolderContainer) {
			rowView.hoveredButton.toolTip = @"New smart folder";
			rowView.hoveredButton.tag = 4;
		} else {
			rowView.hoveredButton.toolTip = @"New folder";
			rowView.hoveredButton.tag = 0;
		}
		
		return rowView;
	}
	
	return [outlineView makeViewWithIdentifier:@"StandardRowView" owner:self];
}


- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
	/// We add a tooltip rectangle for a row representing a folder, to show the numbers of samples in the folder.
	if(![rowView isKindOfClass:HoveredTableRowView.class]) {
		[rowView removeAllToolTips];
		NSRect bounds = rowView.bounds;
		bounds.size.width = 1000; /// We make the rectangle wide enough to make sure the tooltip shows even after the outline view is widened.
		[rowView addToolTipRect:bounds owner:self userData:nil];
	}
}


- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
	NSInteger row = [outlineView rowForView:view];
	if(row >= 0) {
		SampleFolder *folder = [outlineView itemAtRow:row];
		if([folder respondsToSelector:@selector(samples)]) {
			NSInteger nSamples = folder.samples.count;
			return nSamples > 1? [NSString stringWithFormat:@"%ld samples", nSamples] :
			[NSString stringWithFormat:@"%ld sample", nSamples];
		}
	}
	return @"";
}


- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	[SampleTableController.sharedController recordSelectedItems];
	[GenotypeTableController.sharedController recordSelectedItems];
//	SampleFolder *previousSelectedFolder = self.selectedFolder;
	[super outlineViewSelectionDidChange:notification];
/*	if(self.selectedFolder != previousSelectedFolder) {
		NSManagedObjectContext *MOC = previousSelectedFolder.managedObjectContext;
		for(Chromatogram *sample in previousSelectedFolder.samples) {
			if(!sample.hasChanges && !sample.isFault) {
				[MOC refreshObject:sample mergeChanges:NO];
			} else NSLog(@"name: %@", sample.sampleName);
		}
	}*/
}


#pragma mark - management of drop onto the table

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {
	NSPasteboard *pboard = info.draggingPasteboard;
	Folder *destination = [self _folderForItem:item];
	
	/// Implements dropping chromatograms or ABIF files
	if(index < 0 && !destination.isSmartFolder && destination.parent && destination != self.trashFolder) {
		/// Note that we don't allow dropping between rows, which would be possible but disturbing to the user.
		if ([pboard.types containsObject:ChromatogramObjectIDPasteboardType])  {
			/// chromatograms are dragged
			if(destination != self.selectedFolder) {
				return NSDragOperationGeneric;
			}
		}
		if([pboard.types containsObject:NSPasteboardTypeFileURL]) {
			/// files are dragged from the finder
			if(lastDraggingSequence != info.draggingSequenceNumber) {
				lastDraggingSequence = info.draggingSequenceNumber;
				draggedABIFFilePaths = [FileImporter.class ABIFilesFromPboard:pboard];
			}
			if (draggedABIFFilePaths.count > 0) {
				return NSDragOperationCopy;
			}
		}
	}
	
	return [super outlineView:outlineView validateDrop:info proposedItem:item proposedChildIndex:index];
}




- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item
	childIndex:(NSInteger)index {
	
	/// For some reason, the drop doesn't trigger a validation of toolbar items, so we force it.
	[NSApp setWindowsNeedUpdate:YES];
	
	NSPasteboard *pboard = info.draggingPasteboard;
	Folder *destination = [self _folderForItem:item];
	
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if ([pboard.types containsObject:ChromatogramObjectIDPasteboardType]) {
		/// samples are dragged from other folders
		NSMutableArray *draggedSamples = NSMutableArray.new;
		for(NSPasteboardItem *item in pboard.pasteboardItems) {
			/// We have to enumerate the items, because for some reason, `stringForType` called on the pboard returns only
			/// the string for the first item rather than the concatenated string.
			NSString *URIString = [item stringForType:ChromatogramObjectIDPasteboardType];
			Chromatogram *sample = [MOC objectForURIString:URIString expectedClass:Chromatogram.class];
			if(sample) {
				[draggedSamples addObject:sample];
			}
		}
		if(draggedSamples.count > 0) {
			[self.undoManager setActionName:@"Move Sample(s)"];
			[(SampleFolder *)destination addSamples:[NSSet setWithArray:draggedSamples]];
			return YES;
		}
		return NO;
	}
	
	if ([pboard.types containsObject:NSPasteboardTypeFileURL] ) {
		[SampleTableController.sharedController addSamplesFromFiles:draggedABIFFilePaths toFolder:(SampleFolder *)destination];
		return YES;
	}
	
	return [super outlineView:outlineView acceptDrop:info item:item childIndex:index];
}


- (nullable __kindof Folder *)_targetFolderOfSender:(id)sender{
	Folder *targetFolder = [super _targetFolderOfSender:sender];
	if([sender action] == @selector(addFolder:)) {
		/// Here the target folder should be the parent folder of the new folder.
		if([sender respondsToSelector:@selector(tag)] && [sender tag] == 4) {
			/// This tag indicates that the new folder will be a smart folder.
			return self.smartFolderContainer;
		}
		/// The parent folder cannot be a smart folder (or the trash)
		if(targetFolder.isSmartFolder || targetFolder == self.trashFolder) {
			return nil;
		}
	}

	if([sender action] == @selector(editSmartFolder:) && !targetFolder.isSmartFolder) {
		return nil;
	}
	return targetFolder;
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	
	if(menuItem.action == @selector(paste:)) {
		NSPasteboard *pboard = NSPasteboard.generalPasteboard;
		return self.canImportSamples &&
		([pboard.types containsObject:ChromatogramObjectIDPasteboardType] || [pboard.types containsObject:ChromatogramCombinedPasteboardType]);
	}
	
	Folder *targetFolder = [self _targetFolderOfSender:menuItem];
	if(targetFolder && menuItem.action == @selector(addFolder:) && menuItem.tag != 4) {
		menuItem.hidden = NO;
		menuItem.title = targetFolder == self.rootFolder? @"New Folder" : @"Add Subfolder";
		return YES;
	}
	
	return [super validateMenuItem:menuItem];
}


-(void)emptyTrash:(id)sender {
	[self emptyTrashWithCompletionHandler:^(NSError * error) {
	}];
}


- (nullable NSString *)cautionAlertInformativeStringForItems:(NSArray *)items {
	SampleFolder *folder = items.firstObject;
	if(!folder.isSmartFolder) {
		NSInteger sampleCount = folder.allSamples.count;
		if(sampleCount > 0) {
			if(sampleCount > 1) {
				return [NSString stringWithFormat: @"%ld samples in the folder will be deleted. \nThis action can be undone.", sampleCount];
			}
			return @"1 sample in the folder will be deleted. \nThis action can be undone.";
		}
		if(folder.subfolders.count > 0) {
			return @"This action can be undone.";
		}
	}
	return nil;
}


-(IBAction)paste:(id)sender {
	[SampleTableController.sharedController paste:sender];
}

#pragma mark - folder import/export


- (IBAction)addSampleOrSmartFolder:(id)sender {
	[self addFolder:sender];
}


- (IBAction)importFolder:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}
	
	NSOpenPanel* openPanel = NSOpenPanel.openPanel;
	openPanel.prompt = @"Import";
	openPanel.canChooseDirectories = NO;
	openPanel.allowsMultipleSelection = NO;
	openPanel.message = @"Import folder from an archive";
	openPanel.allowedFileTypes = @[@"folderarchive"];
	[openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) {
			NSURL* url = openPanel.URLs.firstObject;
			if(url) {
				[self importFolderFromURL:url];
			}
		}
	}];
}


-(void) importFolderFromURL:(NSURL *)url {
	NSManagedObjectContext *MOC = self.managedObjectContext;
	if(MOC.hasChanges && ![MOC save:nil]) {
		NSError *error = [NSError errorWithDescription:@"The folder could not be imported because an inconsistency in the database." suggestion:@"You may quit the application and try again."];
		[[NSAlert alertWithError: error] beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
		}];
		
		return;
	}
	
	[FileImporter.sharedFileImporter importFolderFromURL:url completionHandler:^(NSError * _Nullable error, SampleFolder * _Nullable importedFolder) {
		if(!error && importedFolder) {
			
			SampleFolder *theFolder = [MOC existingObjectWithID:importedFolder.objectID error:&error];
			if(!error) {
				[self.undoManager setActionName:@"Import Folder"];
				theFolder.parent = self.rootFolder;
				[theFolder autoName];
				[self _addFolderToTable:theFolder];
				[self selectFolder:theFolder];
				[AppDelegate.sharedInstance saveAction:self];
			} else {
				error = [NSError errorWithDescription:@"The folder could not be imported because of an unexpected error." suggestion:@""];
			}
		}
		
		if(error) {
			NSManagedObjectContext *folderContext = importedFolder.managedObjectContext;
			if(folderContext) {
				[folderContext performBlockAndWait:^{
					[folderContext deleteObject:importedFolder];
				}];
			}
			[[NSAlert alertWithError: error] beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
			}];
		}
	}];
	
}


- (NSImage *)exportButtonImageForItems:(NSArray *)items {
	static NSImage * exportImage;
	if(!exportImage) {
		exportImage = [NSImage imageNamed:@"export folder"];
	}
	return exportImage;
}


- (void)exportSelection:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}
	
	SampleFolder *folder = [self _targetFolderOfSender:sender];
	
	if(!folder) {
		return;
	}
	
	NSSavePanel* savePanel = NSSavePanel.savePanel;
	
	savePanel.message = [NSString stringWithFormat:@"Export folder '%@' to an archive", folder.name];
	if(folder.name) {
		savePanel.nameFieldStringValue = folder.name;
	}
	savePanel.allowedFileTypes = @[@"org.jpeccoud.stryper.folderarchive"];
	NSWindow *window = outlineView.window;
	[savePanel beginSheetModalForWindow:window completionHandler:^(NSInteger result){
		if (result == NSModalResponseOK) {
			NSError *error;
			NSURL* fileURL = savePanel.URL;
			if(fileURL) {
				/// we check if the destination is writable before trying to export the folder.
				if(![NSFileManager.defaultManager isWritableFileAtPath:fileURL.URLByDeletingLastPathComponent.path]) {
					error = [NSError errorWithDescription:@"You do not have permission to export the folder at the specified destination." suggestion:@"Choose another destination or change its permissions."];
				}
				
				/// we must save the context before export (as the folder will be materialized in another context)
				BOOL saveError = NO;
				if(folder.managedObjectContext.hasChanges) {
					saveError = ![folder.managedObjectContext save:&error];
					if(error) {
						[MainWindowController.sharedController populateErrorLogWithError:error];
						/// We present a more generic error to the user (the details are in the log).
						error = [NSError errorWithDescription:@"The folder could not be exported because of an inconsistency in the database." suggestion:@"Recent changes will be undone to solve this inconsistency."];
					}
				}
				
				if(error) {
					[NSApp presentError:error];
					if(saveError) {
						[AppDelegate recoverFromErrorInContext:folder.managedObjectContext showLog:YES];
					}
					return;
				}
				
				[self writeFolder:folder ToFile:fileURL completionHandler:^(NSError *error) {
					if(error && error.code != NSUserCancelledError) {
						NSAlert *alert = [NSAlert alertWithError: error];
						[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
						}];
					}
				}];
			}
		}
	}];
}




-(void)writeFolder:(SampleFolder *) folder ToFile: (NSURL *)url completionHandler:(void (^)(NSError *error))callbackBlock  {
	
	ProgressWindow *progressWindow = ProgressWindow.new;
	NSWindow *window = self.tableView.window;
	/// we export the folder in the background (private queue)
	NSManagedObjectContext *MOC = [[AppDelegate.sharedInstance persistentContainer] newBackgroundContext];
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;
	
	[MOC performBlock:^{
		NSError *error;
		SampleFolder *folderToExport = [MOC existingObjectWithID:folder.objectID error:&error];
		if(!error) {
			NSSet *allSamples = folderToExport.allSamples;
			self->exportProgress = [NSProgress progressWithTotalUnitCount:allSamples.count];
			NSProgress *progress = self->exportProgress;
			
			/// monitoring the fraction completed would require counting the samples in the exported folder, which may take time if it has many subfolders
			/// so we don't and we will show an indeterminate indicator. The progress still reports the number of samples being encoded.
			[progress becomeCurrentWithPendingUnitCount:-1];
			self->totalSamplesProcessed = 0;
			[progressWindow showProgressWindowForProgress:progress afterDelay:1.0 modal:YES parentWindow:window];
			if(folderToExport.isSmartFolder) {
				/// a smart folder's content is transferred to a sample folder that we export. We assume that the user wants to export its samples, not the search criteria
				SampleFolder *aFolder = [[SampleFolder alloc] initWithContext:MOC];
				aFolder.name = folderToExport.name;
				aFolder.samples = allSamples;
				folderToExport = aFolder;
			}
			
			NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
			archiver.delegate = self;
			[archiver encodeObject:folderToExport forKey:@"top Folder"];
			NSData *archive = archiver.encodedData;
			
			if(progress.isCancelled) {		/// the progress may have been cancelled by the user
				error = [NSError cancelOperationErrorWithDescription:@"The export has been cancelled by the user." suggestion:@""];
			} else {
				progress.localizedDescription = @"Writing archive to file…";
				progress.cancellable = NO;
				[archive writeToURL:url options:NSDataWritingAtomic error:&error];
			}
			
		} else {
			error = [NSError errorWithDescription:@"The folder could not be exported because an error occurred in the database." suggestion:@"You may quit the application and try again."];
		}
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error);
		}];
		[progressWindow stopShowingProgressAndClose];
	}];
	
}


- (void)archiver:(NSKeyedArchiver *)archiver didEncodeObject:(id)object {
	if([object isKindOfClass:Chromatogram.class]) {
		totalSamplesProcessed++;
		if(totalSamplesProcessed % 100 == 0) {		/// we report every 100 samples encoded
			if(exportProgress) {
				exportProgress.completedUnitCount = totalSamplesProcessed;
				exportProgress.localizedDescription = [NSString stringWithFormat:@"%lu samples encoded", totalSamplesProcessed];
			}
		}
	}
}


- (void)_addFolderToTable:(Folder *)folder {
	/// as the folders show in a pane that can be collapsed, we un-collapse the pane if a new folder is added
	[self showLeftPane];
	[super _addFolderToTable:folder];
}


- (void)selectItemName:(id)item {
	[self showLeftPane];
	[super selectItemName:item];
}


-(void)showLeftPane {
	NSSplitViewItem *leftPane = MainWindowController.sharedController.mainSplitViewController.splitViewItems.firstObject;
	if(leftPane.isCollapsed) {			/// if the bottom pane is collapsed, we make it visible
		[MainWindowController.sharedController.mainSplitViewController toggleSidebar:nil];
	}
}


- (void)deleteItems:(NSArray *)items {
	for(SampleFolder *folder in items) {
		[self _removeFolderFromTable:folder];
		folder.parent = self.trashFolder;
		[folder autoName];						/// to avoid duplicate names in the trash, generating validation errors
	}
}


-(void)emptyTrashWithCompletionHandler:(void (^)(NSError * _Nullable error))callbackBlock {
	SampleFolder *trashFolder = self.trashFolder;
	if(trashFolder.subfolders.count > 0 || trashFolder.samples.count > 0) {
		/// We delete the trash content it in the background to show a process window, in case deletion takes time (lots of items in the trash)
		NSManagedObjectContext *backgroundContext = ((AppDelegate*)NSApp.delegate).persistentContainer.newBackgroundContext;
		ProgressWindow *progressWindow = ProgressWindow.new;
		progressWindow.operationTextField.stringValue = @"Removing deleted items from the database…";
		progressWindow.stopButton.hidden = YES;		/// this operation cannot be cancelled
		NSWindow *window = self.view.window;
		NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;
		[backgroundContext performBlock:^{
			NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
			/// if some folders are deleted, we remove their entries from the genotype filters.
			NSMutableDictionary *genotypeFilters = [userDefaults dictionaryForKey:GenotypeFiltersKey].mutableCopy;
			UserDefaultKey selectedSampleKey = SampleTableController.sharedController.userDefaultKeyForSelectedItemIDs;
			UserDefaultKey selectedGenotypeKey = GenotypeTableController.sharedController.userDefaultKeyForSelectedItemIDs;
			NSMutableDictionary *selectedSamples = [userDefaults dictionaryForKey:selectedSampleKey].mutableCopy;
			NSMutableDictionary *selectedGenotypes = [userDefaults dictionaryForKey:selectedGenotypeKey].mutableCopy;
			BOOL modified = NO;
			NSError *error;
			/// we don't set an `NSProgress` as it would be difficult to monitor the progress of deletion
			[progressWindow showProgressWindowForProgress:nil afterDelay:1.0 modal:YES parentWindow:window];
			SampleFolder *trash = [backgroundContext existingObjectWithID:trashFolder.objectID error:&error];
			if(!error) {
				for(Chromatogram *sample in trash.samples) {
					[backgroundContext deleteObject:sample];
				}
				for(Folder *folder in trash.subfolders) {
					if(!folder.objectID.isTemporaryID) {
						NSString *key = folder.objectID.URIRepresentation.absoluteString;
						[genotypeFilters removeObjectForKey:key];
						[selectedSamples removeObjectForKey:key];
						[selectedGenotypes removeObjectForKey:key];
						modified = YES;
					}
					[backgroundContext deleteObject:folder];
				}
				if(modified) {
					[userDefaults setObject:genotypeFilters forKey:GenotypeFiltersKey];
					[userDefaults setObject:selectedSamples forKey:selectedSampleKey];
					[userDefaults setObject:selectedGenotypes forKey:selectedGenotypeKey];
				}
				if(backgroundContext.hasChanges) {
					[backgroundContext save:&error];
				}
			}
			[progressWindow stopShowingProgressAndClose];
			[callingQueue addOperationWithBlock:^{
				callbackBlock(error);
			}];
		}];
	}
}

#pragma mark - managing sample search


- (IBAction)editSmartFolder:(id)sender {
	
	SmartFolder *targetFolder = [self _targetFolderOfSender:sender];
	if(targetFolder && (!targetFolder.isSmartFolder || !targetFolder.searchPredicate)) {
		return;
	}
	SampleSearchHelper *sharedHelper = SampleSearchHelper.sharedHelper;
	
	[sharedHelper beginSheetModalFoWindow:self.view.window withPredicate:targetFolder.searchPredicate completionHandler:^(NSModalResponse returnCode) {
		if(returnCode == NSModalResponseOK) {
			NSPredicate *predicate = sharedHelper.predicate;
			if(predicate && ![predicate isEqual:targetFolder.searchPredicate]) {
				[self.undoManager setActionName:@"Modify Search Criteria"];
				targetFolder.searchPredicate = predicate;
				if(FolderListController.sharedController.selectedFolder != targetFolder) {
					[FolderListController.sharedController selectFolder:targetFolder];
				}
			}
		}
	}];
	
}





@end
