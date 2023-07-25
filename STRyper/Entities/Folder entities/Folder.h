//
//  Folder.h
//  STRyper
//
//  Created by Jean Peccoud on 23/06/2022.
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




@import CoreData;
#import "CodingObject.h"


NS_ASSUME_NONNULL_BEGIN

/// A container that can be used to build a hierarchy of similar containers.
///
/// A folder is equivalent to a directory in a file manager, and is mostly used as a UI element.
/// It allows building a tree of instances: a folder can have subfolders, each of which may have subfolders.
///
/// A folder also has a name.
@interface Folder : CodingObject

/// The folder's parent folder.
///
/// The reverse relationship is ``subfolders``.
@property (nonatomic, nullable) Folder *parent;

/// The subfolders of the receiver.
///
///	An ordered set is used to allow ordering the subfolders in an arbitrary older.
///
/// The reverse relationship is ``parent``.
@property (nonatomic, nullable) NSOrderedSet <Folder *> *subfolders;

/// The folder's name.
@property (nonatomic) NSString *name;


/// Returns a user-legible string that denotes the folder type.
///
/// The default implementation returns "Folder". Subclasses can override the getter to return another value.
@property (nonatomic, readonly) NSString *folderType;


/// The authorised class of a folder's ``parent``.
///
/// This method accounts for the fact that different subclasses of ``Folder`` may exist and may not be in the same hierarchy.
/// This method is used in ``initWithParentFolder:``, but not in the setters of the ``parent`` and ``subfolders`` relationships.
///
/// By default, this method returns the class of the receiver.
@property (readonly) Class parentFolderClass;

/// Whether the receiver can have subfolders.
///
/// The default value is YES.
@property (readonly, nonatomic) BOOL canTakeSubfolders;


/// Returns a new folder added to a parent folder.
///
/// The new folder is materialized in the managed object context of the `parent`.
///
/// This method returns `nil` if the class of `parent` is not ``parentFolderClass``.
/// - Parameter parent: The folder to be set as the ``parent`` of the returned folder.
-(instancetype)initWithParentFolder: (Folder *)parent;


/// The folders of the same ``folderType`` and that have the same ``parent`` as the receiver.
@property (readonly, nonatomic) NSArray <Folder *> *siblings;


/// Gives the receiver a ``name`` that differs from its ``siblings``.
///
/// This methods adds an integer number to the existing name.
/// If ``name`` returns `nil` or an empty string, the method starts with "Unnamed " appended to ``folderType``.
- (void)autoName;


/**** folder ancestry***/

/// Returns whether the receiver is an ancestor of a folder.
///
/// An "ancestor" of a folder is its ``parent`` or a parent of parent.
/// - Parameter folder: The folder for which the method determines if the receiver is an ancestor.
- (BOOL) isAncestorOf:(Folder *)folder;


/// Returns all the receiver's subfolders, recursively, which includes the subfolders of subfolders.
@property (nonatomic, readonly) NSSet<Folder *> *allSubfolders;

/// The folder's successive ancestors, in order of ancestry.
///
/// If the folder has no parent, this method returns an empty array.
@property (nonatomic, readonly) NSArray<Folder *> *ancestors;

/// The most distant ancestor of the folder.
///
/// If the receiver has no ``parent``, this method returns the receiver.
@property (nonatomic, readonly) Folder *topAncestor;


/**** convenience methods to tell whether a folder is a panel, or a smart folder. We use it as several objects can have folders of different types, and this avoids testing for the folder class. ****/

/// Whether the receiver's class is of kind ``Panel``.
@property (readonly, nonatomic) BOOL isPanel;

/// Whether the receiver's class is of kind ``SmartFolder``.
@property (readonly, nonatomic) BOOL isSmartFolder;



@end


@interface Folder (CoreDataGeneratedAccessors)

- (void)insertObject:(Folder *)value inSubfoldersAtIndex:(NSUInteger)idx;
- (void)removeObjectFromSubfoldersAtIndex:(NSUInteger)idx;
- (void)insertSubfolders:(NSArray<Folder *> *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeSubfoldersAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInSubfoldersAtIndex:(NSUInteger)idx withObject:(Folder *)value;
- (void)replaceSubfoldersAtIndexes:(NSIndexSet *)indexes withSubfolders:(NSArray<Folder *> *)values;
- (void)addSubfoldersObject:(Folder *)value;
- (void)removeSubfoldersObject:(Folder *)value;
- (void)addSubfolders:(NSOrderedSet<Folder *> *)values;
- (void)removeSubfolders:(NSOrderedSet<Folder *> *)values;

@end


NS_ASSUME_NONNULL_END
