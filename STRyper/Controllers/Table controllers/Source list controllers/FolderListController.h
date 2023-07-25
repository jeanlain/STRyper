//
//  FolderListController.h
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



#import "SourceListController.h"
@class SplitViewController;


NS_ASSUME_NONNULL_BEGIN

/// A singleton class that manages the source list of sample folders (``SampleFolder`` objects) and of smart folders (``SmartFolder`` objects).
///
/// This class complements its superclass with internal methods allowing the user to import/export folder archives and to move (``Chromatogram``) objects between folders.
@interface FolderListController : SourceListController <NSKeyedArchiverDelegate> 

/// Convenience method that returns whether the ``SourceListController/selectedFolder`` can accept imported samples.
///
/// The selected folder cannot accept samples it is nil, if it is a ``SmartFolder``, or as no ``Folder/parent``.
@property (readonly) BOOL canImportSamples;

/// Shows the sheets allowing the user edit the target smart folder.
/// - Parameter sender: The object that sent this message.
/// It is analysed by the method to determine the target smart folder
/// (i.e., the one that is selected or the one that is clicked).
- (IBAction)editSmartFolder:(id)sender;

/// Shows the left pane listing folders, if it is collapsed
- (void)showLeftPane;

/// Deletes items that are present in the trash folder in a background queue.
///
/// This method shows a ``ProgressWindow`` one second into the process.
///
/// When finished, a completion handler is called. Its NSError argument is populated by any error that occurred.
- (void)emptyTrashWithCompletionHandler:(void (^)(NSError *error))callbackBlock;
																						
/// Presents an open panel that allows the user to import a folder archive.
///
/// If the user validates, this method imports the archive with via the ``FileImporter`` and presents any error that my have occurred.
///
/// The imported folder is placed at the last position among the ``Folder/subfolders`` of the ``SourceListController/rootFolder``.
/// - Parameter sender: The object that sent this message. It is ignored by the method.
- (IBAction)importFolder:(id)sender;


@end

NS_ASSUME_NONNULL_END
