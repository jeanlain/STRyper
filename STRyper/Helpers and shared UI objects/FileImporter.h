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
@class PanelFolder;
@class SizeStandard;
@class SampleFolder;

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


/// Convenience method that returns paths of files conforming to types from an array of URLs that may point to directories.
///
/// - Parameters:
///   - URLs: Array of file and/or directory URLs.
///   - UTTypes: The types that the files at the `URLs` must conform to.
///   - allowChildren: Whether to return paths from immediate children of directories, if they conform to the `UTTypes`.
+ (NSArray<NSString *>*)pathFromURLs:(NSArray<NSURL *>*) URLs conformingToUTTypes:(NSSet<NSString *> *) UTTypes allowChildren:(BOOL)allowChildren;


/// Convenience method that returns whether an URL points to an item that can be imported or browsed by an open panel that can select directories.
///
///	This method returns `NO` if the URL is a directory that contains files not conforming to the types the panel can import, and which does not contain subdirectories.
/// - Parameters:
///   - URL: An URL.
///   - panel: The panel used to return the `URL`. Validation is based on its `allowedFileTypes`, which is assumed to contained UTTypes.
///   - browse: Whether the method should return `YES` if the `URL` refers to a directory containing subdirectories, even if the directory does not contain valid files.
///   This can be used to allow browsing such directory with the `panel`.
+ (BOOL)isValidURL:(NSURL *)URL forPanel:(NSOpenPanel*) panel browsing:(BOOL) browse;


/// Imports ``Chromatogram`` objects from abif files.
/// 
/// The methods spawns a progress window after 1 second if the progress has not reached at least 50%.
/// Samples are imported in a background queue into a temporary folder. 
/// 
/// The caller is sent a block to execute  every `batchSize` imported samples, and after all files have been processed.
/// When import is finished, this method calls a completion handler with any error that might have occurred.
/// - Parameters:
///   Any number lower than 1 is considered as 1.
///   - filePaths: The paths of ABIF files to import.
///   - batchSize: The number of successfully imported files before `intermediateBlock` is called.
///   - progress: An optional progress that the method updates to indicate the number of files processed.
///   - intermediateBlock: The block sent after `batchSize` files have been imported, and after all files have been processed.
///   The `containerFolderID` parameter contains the `objectID` of newly created folder (with no ``Folder/parent``)
///   whose ``SampleFolder/samples`` are those imported since the last batch. The folder is saved to the persistent store.
///   If the block returns `NO` the import ends, which is interpreted as an error, which will be specified in the `error` parameter of the `callbackBlock`
///   - callbackBlock: The block sent after the import is finished. If an error occurred during the import, the `error` parameter will be populated.
///   If several errors occurred related to unreadable files, they are accessible with the `NSDetailedErrorsKey` key of the `userInfo` dictionary.
- (void)importSamplesFromFiles:(NSArray<NSString *> *)filePaths
					 batchSize:(NSUInteger)batchSize
					  progress:(nullable NSProgress *)progress
		   intermediateHandler:(BOOL (^)(NSManagedObjectID *containerFolderID))intermediateBlock
			 completionHandler: (void (^)(NSError *error))callbackBlock;

/// Imports a folder from an archive.
///  
/// The archive file must conform to `org.jpeccoud.stryper.folderarchive`.
///  
/// The imported folder and its content, as well as imported panel and size standards that have no equivalent in the database
/// are materialized in a ``AppDelegate/childContext``, which is not saved at the end of the import.
///
/// The imported folder and accompanying items, or any error that has occurred, are accessible in `callbackBlock`.
/// - Parameters:
///   - url: The url of the file to import.
///   - importProgress: An optional progress that the method updates to indicate the number of files processed.
///   - callbackBlock: The block called when the import is finished. If an error occurred, the `NSError` parameter will be populated.
-(void)importFolderFromURL:(NSURL *)url progress:(NSProgress *)importProgress completionHandler:(void (^)(NSError *error, SampleFolder *importedFolder))callbackBlock;

@end

NS_ASSUME_NONNULL_END
