//
//  PanelFolder.h
//  STRyper
//
//  Created by Jean Peccoud on 24/11/2022.
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




#import "Folder.h"
@class Panel;

NS_ASSUME_NONNULL_BEGIN


/// A folder containing marker panels (class ``Panel``) or subfolders of its own class.
///
/// A `PanelFolder` allows users to organise marker panels.
/// - Note: ``CodingObject/encodeWithCoder:``  and ``CodingObject/initWithCoder:``  are currently implement in the context of a ``SampleFolder`` unarchiving/archiving,
/// in that the ``Folder/parent`` of the receiver is encoded/decoded, not its ``Folder/subfolders``.
@interface PanelFolder : Folder

/// Returns the receiver's ``Folder/subfolders``  that return `YES` to ``Folder/isPanel``.
- (NSSet<Panel *> *) panels;


/// Returns all the ``panels`` of the folder and its ``Folder/subfolders``, including subfolders of subfolders.
- (NSSet<Panel *> *) allPanels;


/// A string representation of the receiver's ``panels``, which can be used to export it to a text file.
///
/// If the receiver contains at least one panel, the method calls ``Panel/exportString``. Otherwise it returns `nil`.
- (nullable NSString *)exportString;


/// Adds panels decoded from a text file to the receiver's subfolders and returns the decoded panel(s) if no error occurred.
///
/// This method sets the `error` argument if there was a error preventing importing the panels, or a validation error.
///
///	- Returns: The decoded panel, or a folder containing the decoded panels, or `nil` in case of error.
/// - Parameters:
///   - path: The path of the file to import. Its format is described in the ``STRyper`` user guide.
///   - error: On output, any error that occurred.
- (nullable __kindof Folder *) addPanelsFromTextFile:(NSString *)path error:(NSError *__autoreleasing  _Nullable *)error;

- (__kindof NSManagedObject *)entityForType:(NSString *)type withFields:(NSArray <NSString *>*)fields atLine:(int)line ofFile:(NSString *)path error:(NSError *__autoreleasing *)error;

/// When its ``Folder/subfolders`` change, a panel folder posts a notification with this name to the default notification center.
extern NSNotificationName const _Nonnull PanelFolderSubfoldersDidChangeNotification;


@end

NS_ASSUME_NONNULL_END
