//
//  SourceViewController.h
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




#import "SampleFolder.h"
#import "Panel.h"
#import "TableViewController.h"
#import "NSManagedObjectContext+NSManagedObjectContextAdditions.h"

NS_ASSUME_NONNULL_BEGIN


/// An abstract class that provides shared methods for managing outline views (source lists) showing a hierarchy of folders (``Folder`` objects).
///
/// This class implements methods that allow the user to drag ``Folder/subfolders`` between ``Folder/parent`` folders, change their position in their parent, etc.
///
/// The position of a folder in its parent is set by the user, as a source list that this class manages cannot be sorted and only has one column.
///
/// This class manages outline views in which multiple row selection is not allowed.
///
/// In ``STRyper``, this class has two subclasses, one managing the source list of sample folders (``SampleFolder`` and ``SmartFolder``  objects)
/// and the other managing the source list of panels (``Panel`` and ``PanelFolder``  objects).
///
/// NOTE: while this class implements methods to observe folders for changes in their ``Folder/subfolders`` and to update the source list accordingly,
/// other objects should avoid changing parents/subfolders of folders that are shown by the source list.
@interface SourceListController : TableViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>  {

	/// back the readonly  ``selectedFolder`` variable so that it is settable by subclasses.
	__kindof Folder *_selectedFolder;
	
	/// A shortcut to the the outline view the object manages, which is also return by the ``TableViewController/tableView`` property.
	__weak NSOutlineView *outlineView;
}

/// The managed object context of the folders that the class manages, which is the same as ``AppDelegate/managedObjectContext`` of  the application delegate.
///
/// This property is merely defined for convenience, as this class does not use a tree controller bound to a managed object context to manage a source list.
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;

/// The selected folder of the source list that the receiver manages.
@property (nonatomic, readonly, nullable) __kindof Folder *selectedFolder;

/// The folder that is the parent of all other folders of its class (i.e., containing all ``SampleFolder`` objects  except those in the ``trashFolder``, or all ``PanelFolder`` and  ``Panel`` objects).
///
/// This folder shows as a group item on top and the user does not see it as a folder.
@property (nonatomic, readonly) __kindof Folder *rootFolder;
																	
/// The folder containing deleted items (folders or their contents).
@property (nonatomic, readonly, nullable) __kindof Folder *trashFolder;

/// A root folder with no ``Folder/parent`` appearing as a group section in the outline view and which contains all smart folders.
///
/// This property is not relevant for subclasses that do not manage ``SmartFolder`` objects, but  defining it in the superclass facilitates the implementation.
@property (nonatomic, readonly, nullable) SampleFolder *smartFolderContainer;


/// Selects a folder in the source list and returns whether the selection could be made.
///
/// The receiver will expand all parent items of the folder to select.
///
/// Selection may fail if the source list did not find a row corresponding to the folder.
/// - Parameter folder: The folder to select.
- (BOOL)selectFolder:(Folder *)folder;

/// Records the currently selected folder in the user defaults for possible restoration when the app next launches.
- (void)recordSelectedFolder;

/// Overridden by subclass to allow the user to export the selected item of the source list (``SampleFolder`` or ``Panel``).
///
/// The default implementation does nothing.
/// - Parameter sender: The object that sent the message.
- (IBAction)exportSelection:(id)sender;

/// Adds a new folder to the source list.
///
/// The class of the folder to add (``SampleFolder`` or ``SmartFolder``, ``PanelFolder`` or ``Panel``) is encoded in the sender's tag.
/// - Parameter sender: The object that sent this message. It must return an integer for the -tag selector.
/// A tag of 4 will cause the receiver to add a ``SampleFolder`` or a ``Panel``, depending on the receiver class,
/// and other tags will cause it to add a ``SampleFolder`` or a ``PanelFolder``.
- (IBAction)addFolder:(id)sender;



/******************internal methods that are inherited by subclasses, and may at some point end up in a private header*****/

/// Returns a folder for the corresponding item, or nil if the item cannot be associated with a folder.
///
/// This is used within methods that take and id object as an argument, which is the case for many outline view delegate methods 
/// (the item used to be an NSTreeNode when this class was using an NSTreeController).
- (nullable __kindof Folder *)_folderForItem:(id)item ;
														
/// The folder that is the target of an action (sent from the table's contextual menu)
- (__kindof Folder *)_targetFolderOfSender:(id)sender;


/// Removes a folder from the view (doesn't change the model).
///
/// This must be called before the folder is actually deleted or put in the trash in the model.
- (void)_removeFolderFromTable:(Folder *)folder;

/// Similar add a folder to the table, after it has been added to the model.
- (void)_addFolderToTable:(Folder *)folder;

/// The pasteboard type used to allow folder drag & drop.
extern NSPasteboardType _Nonnull const FolderDragType;


@end

NS_ASSUME_NONNULL_END
