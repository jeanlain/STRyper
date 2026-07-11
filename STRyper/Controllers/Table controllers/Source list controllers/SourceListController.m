//
//  SourceViewController.m
//  STRyper
//
//  Created by Jean Peccoud on 18/11/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



#import "SourceListController.h"
#import "MainWindowController.h"
#import "PanelFolder.h"
#import "SampleSearchHelper.h"
#import "SmartFolder.h"
#import "FileImporter.h"

@class Panel;



/// Implementation notes:
/// The outline view does not use a NSTreeController, as changes in the model generally mess with the selected folder and cannot be animated.
/// We instead monitor changes in subfolders (via notifications) and update the view my adding/removing/moving rows.


static void *trashContentChangedContext = &trashContentChangedContext;	/// to give context to KVO. We react when items are added to the trash (or removed, upon undo)



@interface SourceListController ()

/// Folders that may have to be reloaded to the outline view, as their subfolder content has changed
@property (nonatomic) NSMutableSet <__kindof Folder *> *foldersToReload;

@end



@implementation SourceListController {
	BOOL trashContentChanged; /// Set to `YES` after detecting a change in the trash folder content.
}

@synthesize rootFolder = _rootFolder;


- (NSString *)nameForItem:(id)item {
	if([item respondsToSelector:@selector(folderType)]) {
		return [item folderType];
	}
	return @"Folder";
}

- (BOOL)canExportItems {
	return YES;
}

- (void)configureTableContent {
	
	NSManagedObjectContext *MOC = self.managedObjectContext;
	
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(contextDidChange:)
											   name:NSManagedObjectContextObjectsDidChangeNotification object:MOC];
	
	/// we react when the view context saves, to potentially fetch samples.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(contextDidSave:)
												 name:NSManagedObjectContextDidSaveNotification
											   object:MOC];

	
	
	if(!self.rootFolder) {
		/// if there is no root folder, we try to find it in the database
		NSString *entityName = self.entityName;
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
		request.predicate = [NSPredicate predicateWithFormat:@"parent == nil && name == %@", @"__root"];
		NSArray *rootFolders = [MOC executeFetchRequest:request error:nil];
		
		if(rootFolders.count > 1) {
			/// this should not happen, as the UI does not allow creating root folders. But we manage this situation anyway.
			NSLog(@"several root folders found for %@!", entityName);
			_rootFolder = rootFolders.firstObject;
			/// we place other orphan folders in the root folder (otherwise, they won't appear in the outline view)
			for(Folder *folder in rootFolders) {
				if(folder != self.rootFolder) {
					folder.parent = self.rootFolder;
				}
			}
		} else {
			if(rootFolders.count == 0) {		/// this happens at first app launch or if the db has been deleted
				_rootFolder = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:MOC];
			} else {							/// this happens if the preference file has been deleted
				_rootFolder = rootFolders.firstObject;
			}
		}
		self.rootFolder.name = @"__root";
		
		/// if the root folder is empty, we create a sample folder / panel to go inside
		if(self.rootFolder.subfolders.count == 0) {
			if([entityName isEqualToString: PanelFolder.entity.name]) {
				/// if the root folder is a PanelFolder, we add a panel to it, not a PanelFolder.
				entityName = Panel.entity.name;
			}
			Folder *folder = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:MOC];
			folder.parent = self.rootFolder;
			[folder autoName];
			[_rootFolder.managedObjectContext obtainPermanentIDsForObjects:@[_rootFolder] error:nil];
		}
		/// we save a reference of the root folder in the user defaults for quick retrieval
		[NSUserDefaults.standardUserDefaults setObject: self.rootFolder.objectID.URIRepresentation.absoluteString
												forKey:[@"root" stringByAppendingString:self.entityName]];
	}
	
	if(self.rootFolder == nil) {
		NSLog(@"%@:%@ could not create the root folder!", self.class, NSStringFromSelector(_cmd));
		abort();
	}
}


- (void)viewDidLoad {
	[super viewDidLoad];
	
	if(!outlineView) {
		outlineView = (NSOutlineView *)self.tableView;
		outlineView.autosaveExpandedItems = YES;
	}
		
	[self expandFolder:self.rootFolder];
	
	[self restoreSelectedFolder];
	
	/// we observe folders to update the table as required.
	/// But a subclass need not observe all folders. One observes SampleFolders, the other PanelFolders
	/// We could do this within subclasses, but the selector that is called is defined here, so we observe here.
	if([self.entityName isEqualToString: SampleFolder.entity.name]) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(subfoldersDidChange:) name:SampleFolderSubfoldersDidChangeNotification object:nil];
	}
	
	if([self.entityName isEqualToString: PanelFolder.entity.name]) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(subfoldersDidChange:) name:PanelFolderSubfoldersDidChangeNotification object:nil];
	}
	
	if([self.trashFolder respondsToSelector:@selector(samples)]) {
		/// we observe the sample content of the trash folder to update the search results if needed
		/// this should ideally be implemented by our subclass folderListController, but we update the search results when the context changes in contextDidChange:, which is private
		/// we could put contextDidChange: in a private header, ideally.
		[self.trashFolder addObserver:self forKeyPath:@"samples" options:NSKeyValueObservingOptionNew context:trashContentChangedContext];
	}
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(context == trashContentChangedContext) {
		if(self.trashFolder.managedObjectContext.hasChanges) {
			/// The message may be sent when the samples of the trash are accessed at the start of the app
			/// although no sample was put in the trash
			trashContentChanged= YES;
		}
	} else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


-(__kindof Folder *)rootFolder {
	if(!_rootFolder) {
		NSString *uri = [NSUserDefaults.standardUserDefaults stringForKey:[@"root" stringByAppendingString:self.entityName]];
		_rootFolder = [self.managedObjectContext  objectForURIString:uri expectedClass:Folder.class];
		if(_rootFolder.parent || _rootFolder.isSmartFolder || _rootFolder.isPanel) {
			_rootFolder = nil;
		}
	}
	return _rootFolder;
}



# pragma mark - keeping the outline view in sync with the model

- (NSMutableSet<Folder *> *)foldersToReload {
	if(!_foldersToReload) {
		_foldersToReload = NSMutableSet.new;
	}
	return _foldersToReload;
}


-(void)subfoldersDidChange:(NSNotification *)notification {
	Folder *folder = notification.object;
	if(folder.managedObjectContext == self.managedObjectContext && !folder.isDeleted) {
		Folder *trashFolder = self.trashFolder;
		if(folder != trashFolder) { 		/// since we don't show the trash, we don't need to reload it if its content has changed
			if(folder.topAncestor != trashFolder) {
				[self.foldersToReload addObject:folder];
			}
		} else {
			trashContentChanged = YES; 	/// however we note that its content has changed
		}
	}
}


-(void)contextDidChange:(NSNotification *)notification {
	if(trashContentChanged) {
		/// if the trash content has changed, we refresh the content of the selected smart folder, has it should not show samples that are in the trash
		Folder *selectedFolder = self.selectedFolder;
		if(selectedFolder.isSmartFolder) {
			[(SmartFolder *)selectedFolder refresh];
		}
		trashContentChanged= NO;
	}
	
	if(self.foldersToReload.count > 0) {
		if(![self updateOutlineViewWithAnimation]) {
			NSLog(@"forced reloading");
			[self reloadFolders:self.foldersToReload];
		}
		[self.foldersToReload removeAllObjects];
	}
}

-(void) contextDidSave:(NSNotification *)notification {
	/// Some folders tend to be faulted upon save, which makes their names disappear.
	NSMutableIndexSet *rowsToReload = NSMutableIndexSet.new;
	[outlineView enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView * _Nonnull rowView, NSInteger row) {
		Folder *folder = [self itemAtRow:row];
		if(folder.isFault) {
			[rowsToReload addIndex:row];
		}
	}];
	if(rowsToReload.count > 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->outlineView reloadDataForRowIndexes:rowsToReload columnIndexes:[NSIndexSet indexSetWithIndex:0]];
		});
	}
}


-(void)reloadFolders:(NSSet *)folders {
	Folder *selectedFolder = self.selectedFolder;
	for(Folder *parentFolder in folders){
		[outlineView reloadItem:parentFolder reloadChildren:YES];
		[self expandFolder:parentFolder];
	}
	[self selectFolder:selectedFolder];		/// because reloading often deselects a row
}


/// Updates the outline view to reflect the current states of folders, by moving, removing or inserting rows if possible.
/// Returns whether the view was updated.
-(BOOL)updateOutlineViewWithAnimation {
	/// We compare the current state of folders that need refreshing to how their state on the outline view.
	NSArray *folders = self.foldersToReload.allObjects;
	NSInteger folderCount = folders.count;
	if(folderCount > 2 || folderCount == 0) {
		/// We manage changes in two folders at most. As the user can only select a single folder,
		/// a change should not affect more than two parent folders, which happens after dragging a folder between these parents.
		return NO;
	}
	
	BOOL updated = NO; /// Wether the outline view is updated.

	NSArray<NSIndexSet *> *folder1diffs, *folder2diffs;
	NSArray<Folder *> *displayedSubfolders1, *displayedSubfolders2; /// The parents' subfolders as they appear on the outline view
	NSInteger count = 0;
	for(Folder *folder in folders) {
		count++;
		NSArray *displayedSubfolders = [self displayedChildrenOfParent:folder];
		if(displayedSubfolders) {
			NSArray *diffIndexes = [displayedSubfolders indexesOfDifferencesWithArray:folder.subfolders.array];
			if(count == 1) {
				displayedSubfolders1 = displayedSubfolders;
				folder1diffs = diffIndexes;
			} else {
				displayedSubfolders2 = displayedSubfolders;
				folder2diffs = diffIndexes;
			}
		}
	}
	
	BOOL move = NO; /// Whether we move a row to reflect the change.
					/// One folder should have a subfolder that is not shown (the recipient) and the other should show a folder that is not in the model (the source)
	Folder *source = folders.firstObject, *recipient = folders.lastObject; /// Initializes source and recipient assuming the first folder as source.
	NSInteger sourceIndex = folder1diffs.firstObject.firstIndex, recipientIndex = folder2diffs.lastObject.firstIndex;
	NSArray *sourceDisplayedSubFolder = displayedSubfolders1;
	if(folder1diffs.firstObject.count + folder1diffs.lastObject.count == 1 &&
	   folder2diffs.firstObject.count + folder2diffs.lastObject.count == 1 &&
	   folder1diffs.firstObject.count != folder2diffs.firstObject.count) {
		/// The source has one removed object, an no inserted object, and the opposite for the recipient (or reciprocally).
		move = YES;
		if(folder1diffs.lastObject.count > 0) {
			/// If the folder 1 is the recipient, we redefine pointers.
			recipient = folders.firstObject;
			source = folders.lastObject;
			sourceDisplayedSubFolder = displayedSubfolders2;
			sourceIndex = folder2diffs.firstObject.firstIndex;
			recipientIndex = folder1diffs.lastObject.firstIndex;
		}
	} else if(folderCount == 1 && folder1diffs.firstObject.count == 1 && folder1diffs.lastObject.count == 1) {
		/// Case of a move within the same folder. The source and destination are already set properly, but the destination index needs to be specified.
		recipientIndex = folder1diffs.lastObject.firstIndex;
		move = YES;
	}

	NSAnimationContext.currentContext.duration = 0.2;
	[NSAnimationContext beginGrouping];
	[outlineView beginUpdates];
	
	if(move && recipientIndex < recipient.subfolders.count && sourceIndex < sourceDisplayedSubFolder.count &&
	   sourceDisplayedSubFolder[sourceIndex] == [recipient.subfolders objectAtIndex:recipientIndex]) {
		/// Checks that the folder at the destination index in the recipient (model) is the same as the folder in the source at the source index (as displayed)
		
		[outlineView moveItemAtIndex:sourceIndex inParent:source toIndex:recipientIndex inParent:recipient];
		if(source != recipient) {
			[outlineView reloadItem:source];			/// To update disclosure triangles.
			[outlineView reloadItem:recipient];
		}
		updated = YES;
	}
	
	if(!updated) {
		/// Here we don't move a row, but we may add/remove a row, which could reflect the addition/deletion of folders,
		/// or a move when the source or destination if collapsed (in this case, adding/removing a row provides good feedback).
		count = 0;
		NSInteger expanded = 0, inserted = 0; 	/// Wether a folder is expanded during the change, and a row is inserted
		NSArray<NSIndexSet *> *diffs;			/// The indices of rows to remove/add to a given folder.
		for(Folder *folder in folders) {
			count++;
			diffs = count == 1 ? folder1diffs : folder2diffs;
			
			NSIndexSet *removals = diffs.firstObject, *insertions = diffs.lastObject;
			/// There cannot be removals (or insertions) of subfolders in more than one parent, since the view can only select one folder.
			if(removals.count > 0 && insertions.count == 0) {
				[outlineView removeItemsAtIndexes:removals inParent:folder withAnimation:NSTableViewAnimationSlideUp];
				[outlineView reloadItem:folder];
				updated = YES;
			} else if(removals.count == 0 && insertions.count > 0) {
				[outlineView insertItemsAtIndexes:insertions inParent:folder withAnimation:NSTableViewAnimationSlideDown];
				[outlineView reloadItem:folder];
				inserted++;
				updated = YES;
			} else {
				/// Here, the change in subfolders cannot be show, which should mean the parent is collapsed.
				/// We expand it to indicate that a change occurred.
				if((count == 2 && !inserted && !expanded) || (count == 1 && folder2diffs.lastObject.count == 0)) {
					/// We do not expand more than one folder, and we don't if the other folder has an animated insertion
					/// (which should reflect a move between parent folders if two folders must be updated). The insertion is sufficient for feedback.
					[outlineView reloadItem:folder];
					[self openAncestorsOf:folder];
					[outlineView.animator expandItem:folder];
					expanded++;
					updated = YES;
				}
			}
		}
	}
	
	[outlineView endUpdates];
	[NSAnimationContext endGrouping];

	return updated;
}


/// The children of a parent item as they appear on the outline view.
///
/// Returns `nil` if the `parent` has no row or is collapsed.
/// - Parameter parent: An item potentially shown by the view.
-(nullable NSArray*) displayedChildrenOfParent:(id)parent {
	NSInteger folderRow = [self rowForItem:parent];
	if(folderRow < 0 || ![outlineView isItemExpanded:parent]) {
		return nil;
	}
	NSInteger childLevel = [outlineView levelForRow:folderRow]+1;
	NSMutableArray *children = NSMutableArray.new;
	for (NSInteger row = folderRow+1; row < outlineView.numberOfRows; row++) {
		NSInteger rowLevel = [outlineView levelForRow:row];
		if(rowLevel == childLevel) {
			id child = [outlineView itemAtRow:row];
			if(child) {
				[children addObject:child];
			}
		} else if(rowLevel < childLevel) {
			break;
		}
	}
	return children.copy;
}


- (NSString *)actionNameForEditingCellInColumn:(NSTableColumn *)column row:(NSInteger)row {
	Folder *folder = [outlineView itemAtRow:row];
	if(folder) {
		return [@"Rename " stringByAppendingString:folder.folderType];
	}
	return nil;
}


# pragma mark - datasource and delegate methods for the outline view

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	NSInteger number = 0;
	if(item == nil) {
		number = (self.rootFolder != nil) + (self.smartFolderContainer != nil);
	} else {
		if([item respondsToSelector:@selector(subfolders)]) {
			number = [[item subfolders] count];
		}
	}
	return number;
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	if(item == nil) {
		if(index == 0) {
			return self.rootFolder;
		}
		return self.smartFolderContainer;
	}
	if([item respondsToSelector:@selector(subfolders)]) {
		NSOrderedSet *subfolders = [item subfolders];
		if(subfolders.count > index) {
			return [subfolders objectAtIndex:index];
		}
	}
	return NSNull.null;		/// which should never happen
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	return item;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	if([item respondsToSelector:@selector(subfolders)]) {
		return [[item subfolders] count] > 0;
	}
	return NO;
}


- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	Folder *folder = [self _folderForItem:item];
	
	if(folder == self.rootFolder) {
		return [outlineView makeViewWithIdentifier:@"topSection" owner:self];
	}
	if(folder == self.smartFolderContainer || folder == self.rootFolder) {
		return [outlineView makeViewWithIdentifier:@"smartFolderSection" owner:self];
	}
	if(folder == self.trashFolder) {
		/// the trash folder not being a child of the root folder, it is not visible, so this condition should never be met.
		/// But we could change that if we wanted to show the trash
		return [outlineView makeViewWithIdentifier:@"trashCell" owner:self];
	}
	NSTableCellView *view = [outlineView makeViewWithIdentifier:@"mainCell" owner:self];
	if(view.imageView) {
		view.imageView.image = [NSImage imageNamed:folder.folderType];
	}
	if(view.textField) {
		view.textField.delegate = self;
	}
	
	return view;
}



- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
	Folder *folder = [self _folderForItem:item];
	return folder.parent == nil;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
	Folder *folder = [self _folderForItem:item];
	return folder != self.rootFolder;		/// we don't allow collapsing the root folder.
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
	Folder *folder = [self _folderForItem:item];
	return folder.parent != nil;			/// we don't allow selecting group rows.
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item {
	return item != self.rootFolder;
}



# pragma mark - restoring folders at launch


-(nullable __kindof Folder *)_folderForItem:(id)item {
	if([item isKindOfClass:Folder.class]) {
		return item;
	}
	if(![item respondsToSelector:@selector(representedObject)]) {	/// at some point we used a NSTreeController, so this was useful.
		return nil;
	}
	Folder *folder = [item representedObject];
	if(![folder isKindOfClass:Folder.class]) {
		return nil;
	}
	return folder;
}


- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item {
	/// to identify a folder, we use its object id
	Folder *folder = [self _folderForItem:item];
	if(!folder) {
		return @"";
	}
	if(folder.objectID.isTemporaryID) {
		[folder.managedObjectContext obtainPermanentIDsForObjects:@[folder] error:nil];
	}
	return folder.objectID.URIRepresentation.absoluteString;
	
}


- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object {
	if(![object isKindOfClass:NSString.class]) {
		return nil;
	}
	return [self.managedObjectContext objectForURIString:object expectedClass:Folder.class];
}


-(void)setSelectedFolder:(__kindof Folder *)selectedFolder {
	_selectedFolder = selectedFolder;
	[self recordSelectedFolder];
}


- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = outlineView.selectedRow;
	if(row >= 0) {
		Folder *itemAtRow = [outlineView itemAtRow:row];
		if(itemAtRow != self.selectedFolder) {
			self.selectedFolder = itemAtRow;
		}
	} else {
		self.selectedFolder = nil;
	}
}


/// records the currently selected folder for restoration when the app next launches.
- (void)recordSelectedFolder {
	Folder *folder = self.selectedFolder;
	if(folder) {
		if(folder.objectID.isTemporaryID) {
			[folder.managedObjectContext obtainPermanentIDsForObjects:@[folder] error:nil];
		}
		NSString *uri = folder.objectID.URIRepresentation.absoluteString;
		[NSUserDefaults.standardUserDefaults setValue:uri forKey: [@"selected" stringByAppendingString:self.entityName]];
	}
}

/// selects the folder that was selected when the app was terminated
- (void)restoreSelectedFolder {
	NSString *uri = [NSUserDefaults.standardUserDefaults valueForKey:[@"selected" stringByAppendingString:self.entityName]];
	Folder *folder = [self.managedObjectContext  objectForURIString:uri expectedClass:Folder.class];
	if(folder) {
		[self selectFolder:folder];
	} else {
		[self selectFolder: self.rootFolder.subfolders.firstObject];
	}
}


# pragma mark - drag and drop support

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
	/// the user can drag folders (including panels) into other folders. Other types are managed by subclasses
	Folder *draggedFolder = [self _folderForItem:item];
	if(draggedFolder.parent) {
		return draggedFolder;			/// only folders that have parents can be dragged (not folder sections)
	}
	return nil;
}


- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index {
	
	Folder *destination = [self _folderForItem:item];
	if(!destination || destination.isSmartFolder) {
		/// nothing can be dropped outside a folder or into a smart folder
		return NSDragOperationNone;
	}
	
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:FolderDragType]) {
		/// a folder is dragged
			if(!destination.parent && index == -1) {
			/// we don't allow dropping folders onto sections
			return NSDragOperationNone;
		}
		
		Folder *draggedFolder = [self.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
																expectedClass:Folder.class];
		
		if(draggedFolder.parentFolderClass != destination.class) {
			/// this ensures that folders are dropped into folders that can accept them
			return NSDragOperationNone;
		}
				
		if([draggedFolder isAncestorOf:destination]) {
			/// we do not authorise dropping a folder into one of its subfolders (causes a loop)
			/// This is technically possible during a copy-drag, but this would be somewhat counterintuitive.
			return NSDragOperationNone;
		}
		
		if((destination == self.smartFolderContainer) != draggedFolder.isSmartFolder) {
			/// only smart folders can be dropped in this section
			return NSDragOperationNone;
		}
		
		BOOL copy = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0 && [pboard.types containsObject:FolderArchivePasteboardType];
				
		if(!copy) {
			/// we don't move folders to the position they already have
			NSInteger currentIndex = [outlineView childIndexForItem:draggedFolder];
			if(draggedFolder.parent == destination && (index < 0 || index == currentIndex+ 1 || index == currentIndex)) {
				return NSDragOperationNone;
			}
		}
		
		return copy? NSDragOperationCopy : NSDragOperationMove;
		
	}
	return NO;
}



- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
	NSPasteboard *pboard = info.draggingPasteboard;
	if ([pboard.types containsObject:FolderDragType]) {
		Folder *draggedFolder = [self.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
																expectedClass:Folder.class];
		if(!draggedFolder){
			return NO;
		}
		
		Folder	*destination = [self _folderForItem:item];
		if(!destination) {
			return NO;
		}
		
		BOOL copy = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0 && [pboard.types containsObject:FolderArchivePasteboardType];
		
		/// we check if the destination can take the folder (which it cannot if it has a subfolder with the same name).
		/// We did not prevent that in validateDrop: as we want to explain the user why this is not permitted.
		NSError *validationError = nil;
		if(destination != draggedFolder.parent && !copy) {
			[draggedFolder validateValue:&destination forKey:@"parent" error:&validationError];
			if(validationError) {
				[NSApp presentError:validationError];
				return NO;
			}
		}
		
		if(index < 0) {
			index = 0;
		}
		if(index > destination.subfolders.count) {
			index = destination.subfolders.count;
		}
		
		NSInteger sourceIndex = [outlineView childIndexForItem:draggedFolder];
		Folder *sourceParent = [outlineView parentForItem:draggedFolder];
		
		if(copy) {
			return [self addFoldersFromPasteboard:pboard toFolder:destination atIndex:index].count > 0;
		}
		
		if(sourceParent == destination) {
			/// the folder is moved within its parent
			/// we must decrease the destination index if the folder is moved down in the view (hence moved up in the child index)
			if(index > sourceIndex) {
				index--;
			}
			[sourceParent removeSubfoldersObject:draggedFolder]; /// `insertObject:inSubfoldersAtIndex:` below has no effect if the folder is already in the subfolders.
		}
		
		[self.undoManager setActionName:[@"Move " stringByAppendingString: draggedFolder.folderType]];
		[destination insertObject:draggedFolder inSubfoldersAtIndex:index];
		
		[AppDelegate.sharedInstance saveAction:self];
		return YES;
	}
	return NO;
}

- (void)paste:(id)sender {
	NSPasteboard *pboard = NSPasteboard.generalPasteboard;
	Folder *targetFolder = [self _targetFolderOfSender:sender];
	[self addFoldersFromPasteboard:pboard toFolder:(PanelFolder *)targetFolder atIndex:-1];
}


/// Adds folders copied in a pasteboard to a folder and returns the pasted folder(s).
/// - Parameters:
///   - pboard: A paste board containing keys for `FolderArchivePasteboardType`.
///   - destination: The folder to which the pasted folder(s) should be added.
///   - index: The destination index of the pasted folder(s) in the `destination`'s subfolders. If negative, the pasted elements are inserted at the last index.
-(NSArray<Folder *> *) addFoldersFromPasteboard:(NSPasteboard *)pboard toFolder:(Folder *)destination atIndex:(NSInteger)index {
	if(destination == nil || destination.isPanel || destination.isSmartFolder) {
		return nil;
	}
	
	if(index > destination.subfolders.count || index < 0) {
		index = destination.subfolders.count;
	}
		
	NSMutableArray<Folder *> *pastedFolders = NSMutableArray.new;
	NSError *error;

	for(NSPasteboardItem *item in pboard.pasteboardItems) {
		NSData *archivedPanel = [item dataForType:FolderArchivePasteboardType];
		if(archivedPanel) {
			NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archivedPanel error:&error];
			unarchiver.requiresSecureCoding = NO;
			if(!error) {
				unarchiver.delegate = self; /// This allows the panel to be decoded in our managed object context.
				Folder *folder = [unarchiver decodeTopLevelObjectOfClass:Folder.class forKey:NSKeyedArchiveRootObjectKey error:&error];
				[unarchiver finishDecoding];
				if(!error && folder) {
					[destination insertObject:folder inSubfoldersAtIndex:index];
					[folder autoName];
					[pastedFolders addObject:folder];
				}
			}
			if(error) {
				break;
			}
		}
	}
	
	if(error) {
		error = [error errorWithNewDescription:@"The panel could not be pasted due to a database error" suggestion:@""];
		[MainWindowController.sharedController showAlertForError:error];
	}
	
	if(pastedFolders.count > 0) {
		NSString *action = [pboard.name isEqualToString:NSPasteboardNameDrag]? @"Copy" : @"Paste";
		action = [action stringByAppendingFormat:@" %@%@", pastedFolders.firstObject.folderType, pastedFolders.count > 1? @"s": @""];
		[self.undoManager setActionName:action];
		[AppDelegate.sharedInstance saveAction:self];
		[self selectFolder:pastedFolders.firstObject];
	}
	
	return pastedFolders.copy;
}


#pragma mark - editing, removing and renaming folders or panels



- (nullable __kindof Folder *)_targetFolderOfSender:(id)sender {
	Folder *folder = nil;
	if(![sender respondsToSelector:@selector(topMenu)] || [sender topMenu] != outlineView.menu) {
		if([sender action] == @selector(addFolder:) || [sender action] == @selector(addSampleOrSmartFolder:)) {
			/// When adding a folder, the target is the root folder (where a new folder will be added)
			return self.rootFolder;
		}
		return self.selectedFolder;
	}

	NSInteger clickedRow = outlineView.clickedRow;
	if(clickedRow >= 0) {
		folder = [self _folderForItem: [outlineView itemAtRow:clickedRow]];
	} else if([sender action] == @selector(addFolder:) || [sender action] == @selector(addSampleOrSmartFolder:)) {
		/// Even if no row was clicked, we allow adding a folder to the root folder.
		return self.rootFolder;
	} else if([sender action] == @selector(copy:) && ![folder conformsToProtocol:@protocol(NSPasteboardWriting)]) {
		return nil;
	}
	return folder;
}


- (NSString *)deleteActionTitleForItems:(NSArray *)items {
	Folder *folder = items.firstObject;
	
	if(!folder.parent) {
		/// we cannot remove a folder that has no parent (root folder, trash folder, etc.)
		/// although such folder should never be a target for deletion (the UI doesn't allow it).
		return nil;
	}
	
	return [super deleteActionTitleForItems:items];
}


- (nullable NSArray *) validTargetsOfSender:(id)sender  {
	/// overridden because the outline view doesn't use an NSArrayController.
	/// We also use the fact that only one item can be a target (the view doesn't allow multiple selection)
	Folder *folder = [self _targetFolderOfSender:sender];
	return folder == nil? nil : @[folder];
}


- (IBAction)addFolder:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}

	Folder *parentFolder = [self _targetFolderOfSender:sender];
	
	if(parentFolder == self.trashFolder) {
		/// The UI should not allow targeting the trash folder, this a a safety measure.
		return;
	}
	
	Folder *newFolder;
	if(parentFolder.class == PanelFolder.class) {
		if([sender respondsToSelector:@selector(tag)] && [sender tag] == 4) {			/// identifies that we must add a marker panel
			newFolder = [[Panel alloc] initWithParentFolder:parentFolder];
		} else {
			newFolder = [[PanelFolder alloc] initWithParentFolder:parentFolder];
		}
	} else if (parentFolder.class == SampleFolder.class) {
		if([sender respondsToSelector:@selector(tag)] && [sender tag] == 4) {
			/// here, this tag tells that we should create a smart folder
			/// this involve showing the search sheet to the user
			parentFolder = self.smartFolderContainer;	/// For safety, as this should already be the case.
			SampleSearchHelper *searchHelper = SampleSearchHelper.sharedHelper;
			[searchHelper beginSheetModalFoWindow:self.view.window withPredicate:nil completionHandler:^(NSModalResponse returnCode) {
				if(returnCode == NSModalResponseOK) {
					NSPredicate *predicate = searchHelper.predicate;
					if(predicate) {
						Folder *newFolder = [[SmartFolder alloc] initWithParentFolder:(SampleFolder *)parentFolder searchPredicate:predicate];
						[self finishAddingFolder:newFolder];
						[self selectFolder:newFolder];
					}
				}
			}];
			return;
		} else {
			newFolder = [[SampleFolder alloc] initWithParentFolder:parentFolder];
		}
	}
	
	[self finishAddingFolder:newFolder];
}


- (void)expandFolder:(Folder *)folder {
	[outlineView.animator expandItem:folder];
}


/// convenience method that finishes the addition of a new folder
/// we use it to avoid replicating code, as adding a smart folder involves a completion handler, while adding other folder types does not
-(void)finishAddingFolder:(Folder *)folder {
	if(folder) {
		[self.undoManager setActionName:[@"New " stringByAppendingString: folder.folderType]];
		[AppDelegate.sharedInstance saveAction:self];
		[self selectItemName:folder];
	}
}


- (void)selectItemName:(Folder *)item {
	[self openAncestorsOf:item];
	NSInteger row = [outlineView rowForItem:item];
	if(row >= 0) {
		[outlineView editColumn:0 row:row withEvent:nil select:YES];
	}
}



- (void)deleteItems:(NSArray *)items {
	for(Folder *folder in items) {
		[folder.managedObjectContext deleteObject:folder];
	}
	[AppDelegate.sharedInstance saveAction:self];
}




-(void) openAncestorsOf:(Folder *)folder {
	if([outlineView rowForItem:folder] >= 0) {
		/// The folder is already visible.
		return;
	}
	NSArray *ancestors = folder.ancestors;
	if(ancestors.count > 0) {
		/// we start from the most distant ancestor (which can be the root folder)
		ancestors = [[ancestors reverseObjectEnumerator] allObjects];
		for(Folder *ancestor in ancestors) {
			[outlineView.animator expandItem:ancestor];
		}
	}
}


- (BOOL)selectFolder:(Folder *)folder {
	/// The folder may be in a collapsed parent. We expand its ancestors to be able to select it
	[self openAncestorsOf:folder];
	
	NSInteger row = [outlineView rowForItem:folder];
	if(row >= 0) {
		[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		BOOL success = outlineView.selectedRow == row;
		if(success && self.selectedFolder != folder) {
			self.selectedFolder = folder;
		}
		return success;
	} else {
		if(folder == self.selectedFolder) {
			self.selectedFolder = nil;
		}
	}
	return NO;
}



- (void)copyItems:(NSArray *)items ToPasteBoard:(NSPasteboard *)pasteboard {
	[pasteboard clearContents];
	[pasteboard writeObjects:items];
}


- (void)dealloc {
	@try {
		[NSNotificationCenter.defaultCenter removeObserver:self];
	} @catch (NSException *exception) {
	}
}


@end
