//
//  FileImporter.m
//  STRyper
//
//  Created by Jean Peccoud on 27/11/2022.
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


#import "FileImporter.h"
#import "SizeStandard.h"
#import "Chromatogram.h"
#import "SampleFolder.h"

@interface FileImporter () {
	///The total number of sample that have been imported, which is used to monitor the progress of unarchiving.
	NSUInteger totalSamplesProcessed;
}

@property (nullable) NSProgress *importProgress;						/// an object we use to monitor the progress of import
@property (nonatomic) NSManagedObjectContext *childContext;				/// the context used to materialized imported folders

@end

@implementation FileImporter


+ (instancetype)sharedFileImporter {
	static FileImporter *sharedImporter = nil;
	
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		sharedImporter = self.new;
	});
	return sharedImporter;
}

- (BOOL)importOnGoing {
	NSProgress *importProgress = self.importProgress;
	return importProgress && !importProgress.isFinished & !importProgress.isCancelled;
}


# pragma mark - sample import


+ (NSArray <NSString *> *)ABIFilesFromPboard:(NSPasteboard*)pboard {
	
	NSArray *fileURLs = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
	NSMutableArray *filePaths = NSMutableArray.new;
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	for (NSURL *url in fileURLs) {
		NSString *type;
		if ([url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:nil]) {
			if ([workspace type:type conformsToType:@"com.appliedbiosystems.abif.fsa"] || [workspace type:type conformsToType:@"com.appliedbiosystems.abif.hid"]) {
				[filePaths addObject:url.path];
			}
		}
	}
	return filePaths;
	
}


- (void)importSamplesFromFiles:(NSArray<NSString *> *)filePaths
					 batchSize:(NSUInteger)batchSize
					  progress:(nullable NSProgress *)importProgress
		   intermediateHandler:(BOOL (^)(NSManagedObjectID *containerFolderID))intermediateBlock
			 completionHandler:(void (^)(NSError *error))callbackBlock {

	if(self.importOnGoing) {
		NSError *error = [NSError errorWithDescription:@"An import is already ongoing." suggestion:@"Please try again later."];
		callbackBlock(error);
		return;
	}
	
	NSManagedObjectContext *MOC = AppDelegate.sharedInstance.persistentContainer.newBackgroundContext;
	if(!MOC) {
		callbackBlock([NSError errorWithDescription:@"An application error prevented the import!" suggestion:@"You may try to restart."]);
		return;
	}
	
	if(batchSize < 1) {
		batchSize = 1;
	}
		
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;
	NSDate *currentDate = NSDate.date;		/// which we will add as import date for each sample, to make sure the date is the same for all
	NSUInteger nFiles = filePaths.count;
	const NSUInteger reportFileCount = nFiles/100 +1;

	[MOC performBlock:^{
		NSError *error;
		NSMutableArray *fileErrors = NSMutableArray.new;
		importProgress.totalUnitCount = nFiles;
		[importProgress becomeCurrentWithPendingUnitCount:1];
		SampleFolder *folder = [[SampleFolder alloc] initWithContext:MOC];

		NSUInteger numberOfProcessedFiles = 0, numberOfImportedFilesInBatch = 0;
		for (NSString *filePath in filePaths) {
			@autoreleasepool {
				if(importProgress.isCancelled) {
					break;
				}
				NSError *fileError;
				numberOfProcessedFiles++;
				
				Chromatogram *sample = [Chromatogram chromatogramWithABIFFile:filePath addToFolder:folder error:&fileError];
				if(numberOfProcessedFiles % reportFileCount == 0) {
					importProgress.completedUnitCount = numberOfProcessedFiles;
					importProgress.localizedDescription = [NSString stringWithFormat:@"%ld of %ld samples processed",
														   numberOfProcessedFiles, nFiles];
				}
				
				if(fileError) {
					[fileErrors addObject:fileError];
					if(sample) {
						/// in case a Chromatogram object was created, we delete it (though none should be returned if there is an error)
						[sample.managedObjectContext deleteObject:sample];
					}
				} else if(sample) {
					numberOfImportedFilesInBatch++;
					sample.importDate = currentDate;
				}
				if(numberOfImportedFilesInBatch >= batchSize || numberOfProcessedFiles == nFiles) {
					if([MOC save:&error]) {
						if(!intermediateBlock(folder.objectID)) {
							error = [NSError errorWithDescription:@"An application error prevented the import!" suggestion:@"You may try to restart."];
						}
					}
					if(error) {
						break;
					}
					numberOfImportedFilesInBatch = 0;
					if(numberOfProcessedFiles < nFiles) {
						[MOC reset];
						folder = [[SampleFolder alloc] initWithContext:MOC];
					}
				}
			}
		}
		
		[importProgress resignCurrent];
		
		if(importProgress.isCancelled) {
			error = [NSError cancelOperationErrorWithDescription:@"The import was cancelled." suggestion:@""];
		} else if(error) {
				error = [NSError errorWithDescription:@"The sample(s) could not be imported because an error occurred saving the database." suggestion:@"Some sample(s) may contain invalid data."];
				/// hopefully, this kind of error will not happen if the checks made during import are rigorous enough. 
		}
		
		if(!error && fileErrors.count > 0) {
			if(fileErrors.count == 1) {
				error = fileErrors.firstObject;		/// If there was just one problematic file, the error we report is the one associated with this file
			} else {								/// else we indicate the number of failures and include the errors in the user info dictionary
				NSString *description = [NSString stringWithFormat:@"%ld sample(s) could not be imported.", fileErrors.count];
				error = [NSError errorWithDomain:STRyperErrorDomain
											code:NSFileReadCorruptFileError
										userInfo:@{NSDetailedErrorsKey: fileErrors.copy,
												   NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
												   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"See the error log for details.", nil)
													}];
			}
		}
		
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error);
		}];
		
	}];
	
}



# pragma mark - folder import


-(void)importFolderFromURL:(NSURL *)url progress:(NSProgress *)importProgress completionHandler:(void (^)(NSError *error, SampleFolder *importedFolder))callbackBlock {
	if(self.importOnGoing) {
		NSError *error = [NSError errorWithDescription:@"An import is already ongoing." suggestion:@"Please try again later."];
		callbackBlock(error, nil);
		return;
	}
	
	NSManagedObjectContext *MOC = [AppDelegate.sharedInstance newChildContext];
	self.childContext = MOC;
	self.importProgress = importProgress;
	[importProgress becomeCurrentWithPendingUnitCount:-1];
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;

	[MOC performBlock:^{
		SampleFolder *importedFolder;
		NSError *error;
		@autoreleasepool {
			NSData *archive = [NSData dataWithContentsOfURL:url options:NSDataReadingMapped error:&error];
			if(!error) {
				NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archive error:&error];
				if(!error) {
					unarchiver.delegate = self;
					self->totalSamplesProcessed = 0;
					importedFolder = [unarchiver decodeTopLevelObjectOfClass:SampleFolder.class forKey:@"top Folder" error:&error];
					[unarchiver finishDecoding];
				} else{
					error = [NSError fileReadErrorWithDescription:@"The import failed."
													   suggestion:@"The provided file does not correspond to a folder archive or is corrupt."
														 filePath:url.path
														   reason:@"The unarchiver did not validate the data."];
				}
			}
		}
		if(!importProgress.isCancelled) {
			if(!error && importedFolder) {
				[MOC obtainPermanentIDsForObjects:@[importedFolder] error:&error];
				
				if(!error) {
					importProgress.localizedDescription = @"Saving imported data…";
					importProgress.cancellable = NO;
					[MOC save:&error];
				}
				if(error) {		/// an error occurring at this stage means that the folder contains invalid data
								/// we replace the validation error (that would be obscure to the user) within a more generic one
					error = [NSError errorWithDescription:@"The folder could not be imported because it contains invalid data." suggestion:@""];
					importedFolder = nil;
				}
			}
		} else {
			error = [NSError cancelOperationErrorWithDescription:@"The import was cancelled." suggestion:@""];;
		}
		
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error, importedFolder);
		}];
		self.importProgress = nil;
	}];
}



- (id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id)object {
	 if([object isKindOfClass:Chromatogram.class]) {
		totalSamplesProcessed++;
		if(totalSamplesProcessed % 100 == 0) {		/// we report every 100 samples decoded
			self.importProgress.completedUnitCount = totalSamplesProcessed;
			self.importProgress.localizedDescription = [NSString stringWithFormat:@"%ld samples decoded", totalSamplesProcessed];
		}
	 } else if([object isKindOfClass:SizeStandard.class]) {
		 [object autoName]; /// To avoid duplicate names
	 }
	
	return object;
}


@end
