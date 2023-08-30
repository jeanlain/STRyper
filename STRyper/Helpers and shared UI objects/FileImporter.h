//
//  FileImporter.h
//  STRyper
//
//  Created by Jean Peccoud on 27/11/2022.

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


@import  Cocoa;
@class MainWindowController, FolderListController, SampleFolder;

NS_ASSUME_NONNULL_BEGIN

/// A singleton class that manages the import of files (ABIF, folder archives).
///
/// ABIF and folder importations can operate in a background queue, which allows them to show a progress window and to be cancellable.
/// This class implements rudimentary safeguards that prevent launching several imports in parallel, as it does not manage the merging of changes from different contexts.
@interface FileImporter : NSObject <NSKeyedUnarchiverDelegate> {
}

/// I would have rather avoided doing anything in the background, but the user must be able to cancel an import and see the progress.
/// As this app is not thread safe (I know nothing about thread safety), there is only limited measures to avoid some errors or crashes if something bad is done while an import is occurring.
/// The main measure preventing something bad from occurring while an import is ongoing is the presence of the modal progress window, which doesn't show until about 1 sec into the import (during which the user could in principle break the app, if for instance they delete the folder in which samples are imported).


/// The singleton object of this class.
+(instancetype)sharedFileImporter;

/// The context used to materialized imported objects.
@property (nonatomic, readonly) NSManagedObjectContext *childContext;

/// Returns whether an import task is ongoing.
///
/// The singleton instance uses this to avoid launching several import tasks in parallel.
@property (readonly) BOOL importOnGoing;


/// Convenience method that returns paths of ABIF files from a paste board.
///
/// This method find the `NSURL` objects from the paste board that conforms to `com.appliedbiosystems.abif.fsa` or `com.appliedbiosystems.abif.hid`.
///
/// This method can be used to determine which copied or dragged files from the Finder are of the right type.
///
/// - Parameters:
/// 	- pboard: The pasteboard in which to look for ABIF file paths.
/// - Returns:  The file paths for abif files found.
+(NSArray<NSString *> *) ABIFilesFromPboard:(NSPasteboard*)pboard;
	

/// Imports ``Chromatogram`` objects from abif files.
///
/// When it is finished, this method calls a completion handler with any error that might have occurred.
/// If several errors occurred, they are accessible with the `NSDetailedErrorsKey` key of the `userInfo` dictionary.
///
/// The methods spawns a progress window after 1 second if the progress has not reached at least 50%.
/// Samples are imported in a background queue into a temporary folder.
///
/// - Parameters:
///   - filePaths: The paths of ABIF files to import.
///   - callbackBlock: The block called after the import is finished. If an error occurred, the `NSError` parameter will be populated.
///   The `SampleFolder` parameter contains a newly created folder (with no ``Folder/parent``) whose ``SampleFolder/samples`` are those imported.
///   This folder is materialized in a ``AppDelegate/newChildContext``. It  can ben materialized in the parent context, allowing access to its samples in that context.
- (void)importSamplesFromFiles:(NSArray<NSString *> *)filePaths completionHandler: (void (^)(NSError *error, SampleFolder* folder))callbackBlock;


/// Imports a folder from an archive.
///
///	The archive file must conform to `org.jpeccoud.stryper.folderarchive`.
///
/// The imported folder and its content are materialized in a ``AppDelegate/newChildContext``, which is saved at the end of the import.
/// The imported folder is accessible in `callbackBlock` with any error that has occurred (in this case `importedFolder` is `nil`).
///
/// The methods spawns a progress window after 1 second if the process is still ongoing.
/// - Parameters:
///   - url: The url of the file to import.
///   - callbackBlock: The block called when the import is finished. If an error occurred, the `NSError` parameter will be populated.
-(void)importFolderFromURL:(NSURL *)url completionHandler:(void (^)(NSError *error, SampleFolder *importedFolder))callbackBlock;

@end

NS_ASSUME_NONNULL_END
