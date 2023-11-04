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
/// We update the outline view to react to changes in folders in two ways. One is explicit regarding the change that was made and allows animation.
/// The change is defined in methods of this class and describes what the user has done: adding, deleting or moving a folder
/// This allows updating the view with animation, even upon undo/redo.
/// However, if a folder has been modified (with respect to its subfolders) externally, we must also update the table. We use another approach that involves receiving notification from folders and maintaining a set of folders to reload in the table
/// Either way, the table is (generally) updated only when the managed object context commits changes (so as to avoid updating the table too early)


NSString * _Nonnull const FolderDragType = @"org.jpeccoud.stryper.folderDragType";

/// to describe a type of change applied to a folder and to update the view with animation accordingly, we use a dictionary with these keys
typedef NSString *const FolderChangeKey;

/// values for describing the type of folder change
typedef NSString *const FolderChangeDescription;

/// key for the type of folder change. The value must be a FolderChangeDescription
static FolderChangeKey FolderChangeTypeKey = @"FolderChangeTypeKey";
																						
/// denotes that a folder has been deleted
FolderChangeDescription FolderChangeTypeDeletion = @"FolderChangeTypeDeletion",
/// denotes that a folder has been added
FolderChangeTypeAddition = @"FolderChangeTypeAddition",
/// denotes that a folder has been moved
FolderChangeTypeMove = @"FolderChangeTypeMove";

/// key for the folder that is moved/added/deleted. The value must be a folder
FolderChangeKey TargetFolderKey = @"TargetFolderKey",
/// key for the parent folder affected by the change. The value must be a folder
SourceParentKey = @"SourceParentKey",
/// Key for the child index of targetFolder in its parent (e.g., the index of the deletion or insertion). The value must be an unsigned integer.
/// Note that the source and the index do not reflect the actual state of the model, but the state in the view before the change is applied
SourceIndexKey = @"SourceIndexKey",
																						
/// For a FolderChangeTypeMove change, the parent that is the destination of the move. The value must be a folder
DestinationParentKey = @"DestinationParentKey",
/// For a FolderChangeTypeMove change, the child index that is the destination of the move. The value must be an unsigned integer
DestinationIndexKey = @"DestinationIndexKey";

static void *trashContentChangedContext = &trashContentChangedContext;	/// to give context to KVO. We react when items are added to the trash (or removed, upon undo)



@interface SourceListController ()

/// the managed object context of the folders we show
@property (nonatomic) NSManagedObjectContext *managedObjectContext;

/// the dictionary describing the change to make to the view.
@property (nonatomic) NSDictionary *pendingChange;

/// Folders that may have to be reloaded to the outlineview, as their subfolder content has changed
@property (nonatomic) NSMutableSet <__kindof Folder *> *foldersToReload;

/// set to YES after the outlineview is updated with a given change. We use it to avoid redundant changes
@property (nonatomic) BOOL tableUpdated;

/// set to yes after some subfolder are modified, which sometimes nullifies folder names upon saving the context.
/// They names disappear from the table. We use this property to determine if we should restore the names.
/// It would be better to fix the root cause, but I haven't found why folder names (and all other attributes) are sometimes nullified during a save. This appears unpredictable.
@property (nonatomic) BOOL shouldQueryFolderNames;
																	
/// YES if the trash content has changed. We use it to update smart folders so that they don't return samples that are in the trash
@property (nonatomic) BOOL trashContentChanged;

/// to workaround a bug with source list outline views where the indentation level would not be set properly after adding the first subfolder (and a non-group item)
@property (nonatomic) BOOL hasSubfolders;

@end



@implementation SourceListController
@synthesize rootFolder = _rootFolder;


- (NSString *)nameForItem:(id)item {
	if([item respondsToSelector:@selector(folderType)]) {
		return [item folderType];
	}
	return @"Folder";
}


- (void)configureTableContent {
	
	NSManagedObjectContext *MOC = ((AppDelegate *)NSApp.delegate).managedObjectContext;
	[self bind:@"managedObjectContext" toObject:NSApp.delegate withKeyPath:@"managedObjectContext" options:nil];
	
	/// we react to save of the view context, because a save after subfolders are modified sometimes nullifies some attributes of folders, which removes their names from the table
	/// I haven't found a way to prevent this (TO FIX)
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contextDidSave) name:NSManagedObjectContextDidSaveNotification object:MOC];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:MOC];
	
	
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
	
	[outlineView reloadData];
	
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
		self.trashContentChanged = YES;
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
	if(folder.managedObjectContext == self.managedObjectContext) {
		if(folder != self.trashFolder) { 		/// since we don't show the trash, we don't need to reload it if its content has changed
			[self.foldersToReload addObject:folder];
		} else {
			self.trashContentChanged = YES; 	/// however we note that its content has changed
		}
	}
	self.shouldQueryFolderNames = YES;
}


-(void)contextDidChange:(NSNotification *)notification {
	/// this is where we update the outline view if needed, mostly during undo/redo or if another class made change to folders
	if(self.trashContentChanged) {
		/// if the trash content has changed, we refresh the content of the selected smart folder, has it should not show samples that are in the trash
		if(self.selectedFolder.isSmartFolder) {
			[(SmartFolder *)self.selectedFolder refresh];
		}
		self.trashContentChanged = NO;
	}
	
	/// We clear the foldersToReload and the pendingChange as they are only valid now.
	NSDictionary *folderChange;
	if(self.pendingChange) {
		folderChange = [NSDictionary dictionaryWithDictionary: self.pendingChange];
		self.pendingChange = nil;
	}
	
	NSSet *foldersToReload = [NSSet setWithSet:self.foldersToReload];
	[self.foldersToReload removeAllObjects];
	
	if(self.tableUpdated) {
		self.tableUpdated = NO;
		return;
	}
	
	/// if folders have been modified by methods of this class, both pendingChange and foldersToReload properties can be used to update the table.
	/// We use the former, as it describes the change explicitly and allows animation.
	/// Also, foldersToReload sometimes contain folders that didn't have their subfolders changed and which posted their notification for unclear reasons.
	/// NOTE however that if folders are modified in an other class and in this class at the same time (same event loop),
	/// this may cause a problem as some changes may not be reflected in the table.
	/// This should not occur however. 
	/*
	if(foldersToReload.count > 0) {		// disabling TO TEST. This was implemented to check if foldersToReload was consistent with pendingChange, but as said above, the set may contain folders that don't need to be updated
		if(!folderChange || foldersToReload.count > 2) {
			if(foldersToReload.count > 2) {
				NSArray *names = [foldersToReload.allObjects valueForKeyPath:@"@unionOfObjects.name"];
				NSSet *foldersInChange = [NSSet setWithObjects:folderChange[SourceParentKey], folderChange[DestinationParentKey], nil];
				NSArray *names2 = [foldersInChange.allObjects valueForKeyPath:@"@unionOfObjects.name"];

				NSLog(@"reload: %@, change: %@, target: %@",names, names2, [folderChange[TargetFolderKey] name]);
			}
			[self reloadFolders: foldersToReload];
			return;
		}
		NSSet *foldersInChange = [NSSet setWithObjects:folderChange[SourceParentKey], folderChange[DestinationParentKey], nil];
		if(![foldersToReload isSubsetOfSet:foldersInChange]) {
			[self reloadFolders:foldersToReload];
			return;
		}
	}   */
	
	if(folderChange) {
		if([self updateOutlineViewWithFolderChange:folderChange]) {
			return;
		}
	}
	
	if(foldersToReload.count > 0) {
		[self reloadFolders:foldersToReload];
	}
}




-(void)reloadFolders:(NSSet *)folders {
	Folder *selectedFolder = self.selectedFolder;
	for(Folder *parentFolder in folders){
		//NSLog(@"reload: %@", parentFolder.name);
		[outlineView reloadItem:parentFolder reloadChildren:YES];
		[self expandFolder:parentFolder];
	}
	[self selectFolder:selectedFolder];		/// because reloading often deselects a row
}


/// tries to update the outline view according to folderChange and returns whether the update could be performed
-(BOOL)updateOutlineViewWithFolderChange:(NSDictionary *)folderChange {
	Folder *target = folderChange[TargetFolderKey];
	Folder *source = folderChange[SourceParentKey];
	NSNumber *sourceIndexNumber = folderChange[SourceIndexKey];
	NSUInteger sourceIndex = 0;
	if(![target isKindOfClass:Folder.class] || ![source isKindOfClass:Folder.class] || ![sourceIndexNumber respondsToSelector:@selector(unsignedIntValue)]) {
		return NO;
	}
	sourceIndex = sourceIndexNumber.unsignedIntValue;
	
	BOOL folderWasDeleted = [folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeDeletion];
	BOOL folderWasAdded = [folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeAddition];
	BOOL folderWasMoved = [folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeMove];
	
	if(!folderWasMoved && !folderWasDeleted && !folderWasAdded) {
		return NO;
	}
	
	if(folderWasAdded) {
		/// if a folder was added, we check that it  is be present in the source folder at the specified index
		if(sourceIndex >= source.subfolders.count || [source.subfolders objectAtIndex:sourceIndex] != target) {
			return NO;
		}
	}
	
	/// if a folder was deleted from a source at a given index, the source must contain at least as many subfolders as the given index
	if((folderWasDeleted || folderWasMoved) && sourceIndex >= source.subfolders.count+1) {
		return NO;
	}
	
	Folder *destination;
	NSNumber *destinationIndexNumber;
	NSInteger destinationIndex = 0;
	
	if(folderWasMoved) {
		destination = folderChange[DestinationParentKey];
		destinationIndexNumber = folderChange[DestinationIndexKey];
		if(![destination isKindOfClass:Folder.class] || ![destinationIndexNumber respondsToSelector:@selector(unsignedIntValue)]) {
			return NO;
		}
		destinationIndex = destinationIndexNumber.unsignedIntValue;
		/// we check that the destination folder contains that target at the specified index
		if(destinationIndex >= destination.subfolders.count || [destination.subfolders objectAtIndex:destinationIndex] != target) {
			return NO;
		}
	}
	
	/// if we are here, the change will be applied to the table.
	/// For this change to be undoable with animation, we record its reverse
	NSDictionary *reversedChange = [self reversedFolderChangeForChange:folderChange];
	[self.undoManager registerUndoWithTarget:self selector:@selector(setPendingChange:) object:reversedChange];
	
	Folder *currentSelection = self.selectedFolder;		/// to restore the current selection
	
	BOOL sourceExpanded = [outlineView isItemExpanded:source];
	BOOL destinationExpanded = [outlineView isItemExpanded:destination];
	BOOL hasSubfolders = self.hasSubfolders;
	
	NSAnimationContext.currentContext.duration = 0.2;
	[NSAnimationContext beginGrouping];
	[outlineView beginUpdates];
	if(folderWasMoved) {
		if(sourceExpanded || destinationExpanded) {		/// if the source and destination folders are collapsed, we don't need to move the row
			[outlineView moveItemAtIndex:sourceIndex inParent:source toIndex:destinationIndex inParent:destination];
		}
		[outlineView reloadItem:destination];
	} else if(folderWasAdded) {
		[outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:sourceIndex] inParent:source withAnimation:NSTableViewAnimationSlideDown];
		[outlineView expandItem:source];
	} else if(folderWasDeleted) {
		[outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:sourceIndex] inParent:source withAnimation:NSTableViewAnimationSlideUp];
	}
	if(folderWasAdded && !hasSubfolders && self.hasSubfolders && source.parent) {		
		/// if this is the first subfolder of a non-group parent (i.e. its parent is not the root folder), we reload its grandparent (which should be the root) and parents. 
		/// Otherwise, the indentation level may not be set properly
		/// this is because the source list outline view style does not indent the children of group items if they don't themselves have children.
		/// This leaves no space for the the outline button (triangle). Adding an item via insertItemsAtIndexes does not correct for the absence of space. We must reload.
		[outlineView reloadItem:source.parent reloadChildren:YES];
	} else {
		[outlineView reloadItem:source];
	}
	[outlineView endUpdates];
	[NSAnimationContext endGrouping];
	
	if(target == currentSelection) {
		[self selectFolder:currentSelection];
	}
	return YES;
}


/// returns the reverse change of a change in folder
/// It doesn't control if the dictionary has valid entries
-(NSDictionary *)reversedFolderChangeForChange:(NSDictionary *)folderChange {
																					
	NSDictionary *reversed;
	if([folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeMove]) {
		reversed = @{FolderChangeTypeKey: FolderChangeTypeMove,
					 TargetFolderKey: folderChange[TargetFolderKey],
					 SourceParentKey: folderChange[DestinationParentKey],
					 SourceIndexKey: folderChange[DestinationIndexKey],
					 DestinationParentKey: folderChange[SourceParentKey],
					 DestinationIndexKey: folderChange[SourceIndexKey]};
		
	} else if([folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeAddition]) {
		reversed = @{FolderChangeTypeKey: FolderChangeTypeDeletion,
					 TargetFolderKey: folderChange[TargetFolderKey],
					 SourceParentKey: folderChange[SourceParentKey],
					 SourceIndexKey: folderChange[SourceIndexKey]};
	} else if([folderChange[FolderChangeTypeKey] isEqualToString:FolderChangeTypeDeletion]) {
		reversed = @{FolderChangeTypeKey: FolderChangeTypeAddition,
					 TargetFolderKey: folderChange[TargetFolderKey],
					 SourceParentKey: folderChange[SourceParentKey],
					 SourceIndexKey: folderChange[SourceIndexKey]};
	}
	return reversed;
}


-(void)contextDidSave {
	if(self.shouldQueryFolderNames) {
		///we query the name of folders shown in the view, which thankfully restores their name if they have become nil
		[outlineView enumerateAvailableRowViewsUsingBlock:^(__kindof NSTableRowView * _Nonnull rowView, NSInteger row) {
			Folder *folder = [outlineView itemAtRow:row];
			if([folder respondsToSelector:@selector(name)] && !folder.name) {
				NSLog(@"no name");		/// which hopefully shouldn't be logged, as accessing the name just above restores the name
			}
		}];
	}
	self.shouldQueryFolderNames = NO;
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
			return [[item subfolders] objectAtIndex:index];
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
	return view;
}



- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
	Folder *folder = [self _folderForItem:item];
	return folder.parent == nil;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
	Folder *folder = [self _folderForItem:item];
	if(folder.parent) {
		self.hasSubfolders = YES;
	}
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
}


- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = outlineView.selectedRow;
	if(row >= 0) {
		Folder *itemAtRow = [outlineView itemAtRow:row];
		if(itemAtRow != self.selectedFolder) {
			self.selectedFolder = itemAtRow;
		}
	}
}


/// records the currently selected folder for restoration when the app next launches.
- (void)recordSelectedFolder {
	Folder *folder = self.selectedFolder;
	if(folder) {
		NSString *uri = folder.objectID.URIRepresentation.absoluteString;
		[NSUserDefaults.standardUserDefaults setValue:uri forKey: [@"selected" stringByAppendingString:self.entityName]];
	}
}


- (void)restoreSelectedFolder {				/// selects the folder that was selected when the app was terminated
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
	/// the user can drag folders (including panels and smart folders) into other folders. Other types are managed by subclasses
	Folder *draggedFolder = [self _folderForItem:item];
	if(!draggedFolder.parent) {
		return nil;			/// we don't allow dragging folder sections
	}
	/// we identify the dragged folder by its object ID.
	if(draggedFolder.objectID.isTemporaryID) {
		if(![draggedFolder.managedObjectContext obtainPermanentIDsForObjects:@[draggedFolder] error:nil]) {
			return nil;
		}
	}
	NSPasteboardItem *pasteBoardItem = NSPasteboardItem.new;
	[pasteBoardItem setString:draggedFolder.objectID.URIRepresentation.absoluteString forType:FolderDragType];
	return pasteBoardItem;
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
		Folder *draggedFolder = [self.managedObjectContext objectForURIString:[pboard stringForType:FolderDragType]
																expectedClass:Folder.class];
		if(!destination.parent && index == -1) {
			/// we don't allow dropping folders onto sections
			return NSDragOperationNone;
		}
		
		if(draggedFolder.parentFolderClass != destination.class) {
			/// this ensures that folders are dropped into folders that can accept them
			return NSDragOperationNone;
		}
		
		if([draggedFolder isAncestorOf:destination]) {
			/// we do not authorise dropping a folder into one of its subfolders (causes a loop)
			return NSDragOperationNone;
		}
		
		if((destination == self.smartFolderContainer) != draggedFolder.isSmartFolder) {
			/// only smart folders can be dropped in this section
			return NSDragOperationNone;
		}
		
		NSInteger currentIndex = [outlineView childIndexForItem:draggedFolder];
		
		/// we don't drop folders in the position they already have
		if(draggedFolder.parent == destination && (index < 0 || index == currentIndex+ 1 || index == currentIndex)) {
			return NSDragOperationNone;
		}
		
		return NSDragOperationMove;
		
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
		
		/// we check if the destination can take the folder (which it cannot if it has a subfolder with the same name).
		/// We did not prevent that in validateDrop: as we want to explain the user why this is not permitted
		NSError *validationError = nil;
		if(destination != draggedFolder.parent) {
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
		Folder *originalParent = [outlineView parentForItem:draggedFolder];
		
		if(originalParent == destination) {
			/// the folder is moved within its parent
			/// we must decrease the destination index if the folder is moved down in the view (hence moved up in the child index)
			if(index > sourceIndex) {
				index--;
			}
			/// insertObject:inSubfoldersAtIndex: has no effect within the same parent. And core data doesn't appear to provide a method that reorders the elements (only on that can replace elements)
			/// We could achieve what we want by first removing the folder from the parent and inserting it at another place, but I prefer avoiding that. 
			NSMutableOrderedSet *subfolders = [NSMutableOrderedSet orderedSetWithOrderedSet:originalParent.subfolders];
			[subfolders moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:sourceIndex] toIndex:index];
			originalParent.subfolders = [NSOrderedSet orderedSetWithOrderedSet:subfolders];
		} else {
			[destination insertObject:draggedFolder inSubfoldersAtIndex:index];
		}
		
		self.pendingChange = @{FolderChangeTypeKey: FolderChangeTypeMove,
							   TargetFolderKey: draggedFolder,
							   SourceParentKey: originalParent,
							   SourceIndexKey: @(sourceIndex),
							   DestinationParentKey: destination,
							   DestinationIndexKey: @(index)
		};
		/// it is better to update the table now.
		/// If we do it in contextDidChange, the dragged folder ends up taking two identical rows if the destination is collapsed and already has folders.
		self.tableUpdated = [self updateOutlineViewWithFolderChange:self.pendingChange];
																								
		
		[self.undoManager setActionName:[@"Move " stringByAppendingString: draggedFolder.folderType]];
		return YES;
	}
	return NO;
}



#pragma mark - editing, removing and renaming folders or panels



- (__kindof Folder *)_targetFolderOfSender:(id)sender {
	return [self targetItemsOfSender:sender].firstObject;
}


- (void)menuNeedsUpdate:(NSMenu *)menu {
	
	if(menu == outlineView.menu) {
		Folder *targetFolder = [self _targetFolderOfSender:menu];
		BOOL hide = targetFolder.parent == nil;
		for(NSMenuItem *menuItem in menu.itemArray) {
			menuItem.hidden = hide;
		}
	} else {
		[super menuNeedsUpdate:menu];
	}
	
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	BOOL response = [super validateMenuItem:menuItem];
	if(!response) {
		return NO;
	}
	Folder *targetFolder = [self _targetFolderOfSender:menuItem];
	BOOL hide = targetFolder.parent == nil;
	menuItem.hidden = hide;
	return !hide;
}


- (NSString *)removeActionTitleForItems:(NSArray *)items {
	Folder *folder = items.firstObject;
	
	if(!folder.parent) {
		/// we cannot remove a folder that has no parent (root folder, trash folder, etc.)
		return nil;
	}
	
	return [super removeActionTitleForItems:items];
}


- (nullable NSArray *) targetItemsOfSender:(id)sender  {
	/// overridden because the outline view doesn't use an NSArrayController.
	/// We also use the fact that only one item can be a target (the view doesn't allow multiple selection)
	Folder *folder = nil;
	NSInteger row = -1;
	if(sender == outlineView.menu || ([sender respondsToSelector:@selector(topMenu)] && [sender topMenu] == outlineView.menu)) {
		row = outlineView.clickedRow;
	} else {
		row = outlineView.selectedRow;
	}
	if(row >= 0) {
		folder = [self _folderForItem: [outlineView itemAtRow:row]];
	}
	if(!folder) {
		return nil;
	}
	return @[folder];
	
}


- (IBAction)addFolder:(id)sender {
	if(FileImporter.sharedFileImporter.importOnGoing) {
		return;
	}

	Folder *parentFolder = self.rootFolder;
	
	if(outlineView.clickedRow >=0) {
		/// it a folder is right-clicked, we add a new subfolder (or pane) as a last child
		parentFolder = [self _folderForItem:[outlineView itemAtRow:outlineView.clickedRow]];
	}
	
	if(!parentFolder || parentFolder == self.trashFolder) {
		return;
	}
	
	Folder *newFolder;
	if(parentFolder.class == PanelFolder.class) {
		if([sender respondsToSelector:@selector(tag)] && [sender tag] == 4) {			/// identifies if we must add a marker panel
			newFolder = [[Panel alloc] initWithParentFolder:parentFolder];
		} else {
			newFolder = [[PanelFolder alloc] initWithParentFolder:parentFolder];
		}
	} else if (parentFolder.class == SampleFolder.class) {
		if([sender respondsToSelector:@selector(tag)] && [sender tag] == 4) {
			/// here, this tag tells that we should create a smart folder
			/// this involve showing the search sheet to the user
			parentFolder = self.smartFolderContainer;
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
	[outlineView expandItem:folder];
}


/// convenience method that finishes the addition of a new folder
/// we use it to avoid replicating code, as adding a smart folder involves a completion handler, while adding other folder types does not
-(void)finishAddingFolder:(Folder *)folder {
	if(folder) {
		[self.undoManager setActionName:[@"New " stringByAppendingString: folder.folderType]];
		[self _addFolderToTable:folder]; /// we add the folder directly as we want to select the item name
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



-(void)_addFolderToTable:(Folder *)folder {
	Folder *parent = folder.parent;
	if(!parent) {
		return;
	}
	self.pendingChange = @{FolderChangeTypeKey: FolderChangeTypeAddition,
						   TargetFolderKey:folder,
						   SourceParentKey:parent,
						   SourceIndexKey:@([parent.subfolders indexOfObject:folder])};
	self.tableUpdated = [self updateOutlineViewWithFolderChange:self.pendingChange];
}


- (void)removeItems:(NSArray *)items {
	for(Folder *folder in items) {
		[self _removeFolderFromTable:folder];
		[folder.managedObjectContext deleteObject:folder];
	}
}


-(void) _removeFolderFromTable:(Folder *)folder {
	Folder *parent = folder.parent;
	if(!parent || folder.managedObjectContext != self.managedObjectContext) {
		return;
	}
	NSUInteger index = [parent.subfolders indexOfObject:folder];
	
	self.pendingChange = @{FolderChangeTypeKey: FolderChangeTypeDeletion,
						   TargetFolderKey:folder,
						   SourceParentKey:parent,
						   SourceIndexKey:@(index)};
}



-(void) openAncestorsOf:(Folder *)folder {
	NSArray *ancestors = folder.ancestors;
	if(ancestors.count > 0) {
		/// we start from the most distant ancestor (which can be the root folder)
		ancestors = [[ancestors reverseObjectEnumerator] allObjects];
		for(Folder *ancestor in ancestors) {
			[outlineView expandItem:ancestor];
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


- (void)exportSelection:(id)sender {
	/// overridden
}


- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}


@end
