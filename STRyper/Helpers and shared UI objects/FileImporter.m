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


#import "MainWindowController.h"
#import "FileImporter.h"
#import "SizeStandard.h"
#import "FolderListController.h"
#import "Chromatogram.h"
#import "ProgressWindow.h"
#import "PanelListController.h"
#import "PanelFolder.h"
#import "Panel.h"
#import "SizeStandard.h"
#import "Genotype.h"
#import "Mmarker.h"

@interface FileImporter () {
	///The total number of sample that have been imported, which is used to monitor the progress of unarchiving.
	NSUInteger totalSamplesProcessed;
}

@property (nullable) NSProgress *importProgress;						/// an object we use to monitor the progress of import
@property (nonatomic) NSManagedObjectContext *childContext;				/// the context used to materialized imported folders
@property (nonatomic) NSMutableSet<Folder *> *importedRootPanels;		/// the top ancestors of imported panels that we retain after importing a folder
@property (nonatomic) NSMutableSet<Folder *> *rootFolderPanels;			/// the top ancestors of all imported panels. We make the difference with the importedRootPanels to determine which to delete when unarchiving is finished

@end

@implementation FileImporter


static NSDictionary *standardForKey;		///this is used to deduce the size standard used in the electrophoresis based on a string in the standard name ("StdF" element in the ABIF file)


+ (instancetype)sharedFileImporter {
	static FileImporter *sharedImporter = nil;
	
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		sharedImporter = self.new;
	});
	return sharedImporter;
}

- (BOOL)importOnGoing {
	return self.importProgress != nil;		
}

+ (void)initialize {
	if (self == FileImporter.class) {
		standardForKey =
		@{
			@"500": @"GeneScan-500",
			@"400": @"GeneScan-400HD",
			@"350": @"GeneScan-350",
			@"600": @"GeneScan-600"
		};
	}
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
		   intermediateHandler:(void (^)(SampleFolder* folder))intermediateBlock
			 completionHandler: (void (^)(NSError *error))callbackBlock {

	if(self.importOnGoing) {
		NSError *error = [NSError errorWithDescription:@"An import is already ongoing." suggestion:@"Please try again later."];
		callbackBlock(error);
		return;
	}
	
	if(batchSize < 1) {
		batchSize = 1;
	}
		
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;
	BOOL applySizeStandard = [NSUserDefaults.standardUserDefaults boolForKey:AutoDetectSizeStandard];
	NSDate *currentDate = NSDate.date;		/// which we will add as import date for each sample, to make sure the date is the same for all
	NSUInteger nFiles = filePaths.count;
	NSUInteger reportFileCount = nFiles/100 +1;
	ProgressWindow *progressWindow = ProgressWindow.new;
	NSWindow *window = MainWindowController.sharedController.window;
	NSManagedObjectContext *MOC = ((AppDelegate*)NSApp.delegate).newChildContext;

	[MOC performBlock:^{
		NSError *error;
		NSMutableArray *fileErrors = NSMutableArray.new;
		self.importProgress = [NSProgress progressWithTotalUnitCount:nFiles];
		[progressWindow showProgressWindowForProgress:self.importProgress afterDelay:1.0 modal:YES parentWindow:window];
		[self.importProgress becomeCurrentWithPendingUnitCount:1];
		SampleFolder *folder = [[SampleFolder alloc] initWithContext:MOC];
		[MOC obtainPermanentIDsForObjects:@[folder] error:nil];
		[folder autoName]; /// To avoid a validation error.

		NSUInteger numberOfProcessedFiles = 0, numberOfImportedFilesInBatch = 0;
		for (NSString *filePath in filePaths) {
			if(self.importProgress.isCancelled) {
				break;
			}
			NSError *fileError;
			numberOfProcessedFiles++;
			
			Chromatogram *sample = [Chromatogram chromatogramWithABIFFile:filePath addToFolder:folder error:&fileError];
			if(numberOfProcessedFiles % reportFileCount == 0) {
				self.importProgress.completedUnitCount = numberOfProcessedFiles;
				self.importProgress.localizedDescription = [NSString stringWithFormat:@"%ld of %ld samples processed",
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
				if(applySizeStandard) {
					[self autoDetectSizeStandardOnSample:sample];
				}
				if(!sample.sizeStandard) {
					/// even if we don't apply a size standard, we make the sample compute default sizing coefficients
					[sample setLinearCoefsForReadLength:DefaultReadLength];
				}
			}
			if(numberOfImportedFilesInBatch >= batchSize || numberOfProcessedFiles == nFiles) {
				numberOfImportedFilesInBatch = 0;
				[folder.managedObjectContext save:&error];
				[callingQueue addOperationWithBlock:^{
					intermediateBlock(folder);
				}];
				if(numberOfProcessedFiles < nFiles) {
					folder = [[SampleFolder alloc] initWithContext:MOC];
					[MOC obtainPermanentIDsForObjects:@[folder] error:nil];
					[folder autoName];
				}
			}
		}
		
		[self.importProgress resignCurrent];
		
		if(self.importProgress.isCancelled) {
			error = [NSError cancelOperationErrorWithDescription:@"The import was cancelled after." suggestion:@""];
		} else if(folder.samples.count > 0 && folder.managedObjectContext.hasChanges) {
			self.importProgress.localizedDescription = @"Saving imported data…";
			self.importProgress.cancellable = NO;
			[folder.managedObjectContext save:&error];
			
			if(error) {
				error = [NSError errorWithDescription:@"The sample(s) could not be imported because an error occurred saving the database." suggestion:@"Some sample(s) may contain invalid data."];
				/// hopefully, this kind of error will not happen if the checks made during import are rigorous enough. 
				/// Because the error reported during save does not allow finding which samples caused problems
			}
		}
		
		if(!error && fileErrors.count >0) {
			if(fileErrors.count == 1) {
				error = fileErrors.firstObject;		/// if there was just one problematic file, the error we report is the one associated with this file
			} else {								/// else we indicate the number of failures and include the errors in the user info dictionary
				NSString *description = [NSString stringWithFormat:@"%ld sample(s) could not be imported.", fileErrors.count];
				error = [NSError errorWithDomain:STRyperErrorDomain
											code:NSFileReadCorruptFileError
										userInfo:@{NSDetailedErrorsKey: [NSArray arrayWithArray:fileErrors],
												   NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
												   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"See the error log for details.", nil)
													}];
			}
		}
		
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error);
		}];
		
		[progressWindow stopShowingProgressAndClose];
		self.importProgress = nil;
	}];
	
}


-(void) autoDetectSizeStandardOnSample:(Chromatogram *)sample {
	/// we attribute a size standard based on the standardName attribute of the sample
	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:SizeStandard.entity.name];
	
	NSString *standardName = sample.standardName;
	fetchRequest.predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"%@ LIKE '%@'", SizeStandardNameKey, standardName]];
	NSArray *fetchedSizeStandard = [sample.managedObjectContext executeFetchRequest:fetchRequest error:nil];
	if(fetchedSizeStandard.count == 0) {			/// if there is no size standard whose name correspond to the sample attribute, we try to attribute a size standard based on part of the name, in this case the size range
		
		for (NSString *key in standardForKey) {
			if ([sample.standardName rangeOfString:key].location != NSNotFound) {
				standardName = standardForKey[key];
				fetchRequest.predicate = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"%@ LIKE '%@'", SizeStandardNameKey, standardName]];
				fetchedSizeStandard = [sample.managedObjectContext executeFetchRequest:fetchRequest error:nil];
				if (fetchedSizeStandard.count > 0) {
					break;
				}
			}
		}
	}
	
	if (fetchedSizeStandard.count > 0) {
		sample.sizeStandard = fetchedSizeStandard.firstObject;
	}
}


# pragma mark - folder import


-(void)importFolderFromURL:(NSURL *)url completionHandler:(void (^)(NSError *error, SampleFolder *importedFolder))callbackBlock {
	if(self.importOnGoing) {
		NSError *error = [NSError errorWithDescription:@"An import is already ongoing." suggestion:@"Please try again later."];
		callbackBlock(error, nil);
		return;
	}
	
	ProgressWindow *progressWindow = ProgressWindow.new;
	NSWindow *window = MainWindowController.sharedController.window;
	self.childContext = [AppDelegate.sharedInstance newChildContext];
	self.importProgress = [NSProgress progressWithTotalUnitCount:-1];
	[self.importProgress becomeCurrentWithPendingUnitCount:-1];
	NSOperationQueue *callingQueue = NSOperationQueue.currentQueue;

	[self.childContext performBlock:^{
		[progressWindow showProgressWindowForProgress:self.importProgress afterDelay:1.0 modal:YES parentWindow:window];
		SampleFolder *importedFolder;
		NSError *error;
		NSData *archive = [NSData dataWithContentsOfURL:url options:NSDataReadingMapped error:&error];
		if(!error) {
			NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archive error:&error];
			if(!error) {
				unarchiver.delegate = self;
				self->totalSamplesProcessed = 0;
				importedFolder = [unarchiver decodeTopLevelObjectOfClass:SampleFolder.class forKey:@"top Folder" error:&error];
				[unarchiver finishDecoding];
			} else{
				error = [NSError fileReadErrorWithDescription:@"The import could not proceed."
												   suggestion:@"The provided file does not correspond to a folder archive or is corrupt."
													 filePath:url.path
													   reason:@"The unarchiver did not validate the data."];
			}
		}
		
		if(!self.importProgress.isCancelled) {
			if(!error && importedFolder) {
				if(self.importedRootPanels.count > 0) {		/// some panels may have been imported with the folder. If so, they are listed here
															/// we place them in a separate PanelFolder named after the imported folder
					PanelFolder *rootPanelFolder = [self.childContext existingObjectWithID:PanelListController.sharedController.rootFolder.objectID error:nil];
					if(rootPanelFolder) {
						PanelFolder *folderForImportedPanels = [[PanelFolder alloc] initWithParentFolder:rootPanelFolder];
						folderForImportedPanels.name = [importedFolder.name stringByAppendingString:@" - imported panels"];
						[folderForImportedPanels autoName];
						for(PanelFolder *panel in self.importedRootPanels) {
							panel.parent = folderForImportedPanels;
						}
					}
					[self.importedRootPanels removeAllObjects];
				}
				
				if(self.childContext.hasChanges) {
					[self.childContext obtainPermanentIDsForObjects:@[importedFolder] error:nil];
					self.importProgress.localizedDescription = @"Saving imported data…";
					self.importProgress.cancellable = NO;
					[self.childContext save:&error];
					
					if(error) {		/// an error occurring at this stage means that the folder contains invalid data
									/// we replace the validation error (that would be obscure to the user) within a more generic one
						error = [NSError errorWithDescription:@"The folder could not be imported because it contains invalid data." suggestion:@""];
						importedFolder = nil;
					}
				}
			}
		} else {
			importedFolder = nil;		/// if the import has been cancelled, no folder should be returned
			error = [NSError cancelOperationErrorWithDescription:@"The user cancelled the import." suggestion:@""];;
		}
		
		[callingQueue addOperationWithBlock:^{
			callbackBlock(error, importedFolder);
		}];
		
		[progressWindow stopShowingProgressAndClose];
		self.importProgress = nil;
	}];
}



- (id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id)object {
	if([object class] == Panel.class) {
		/// A panel decoded from an archive may have an identical panel in the store. If so, we return the existing panel
		Panel *decodedPanel = (Panel *)object;
		/// we fetch the existing panels. It would be a bit faster to do it once for all before import, but there shouldn't be many panels imported at once
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:Panel.entity.name];
		NSArray *existingPanels = [decodedPanel.managedObjectContext executeFetchRequest:request error:nil];
		/// we record the top ancestor of the panel, which we may have to delete if the panel gets replaced by one in the store
		[self.rootFolderPanels addObject:decodedPanel.topAncestor];
		for(Panel *panel in existingPanels) {
			if(panel != decodedPanel && [decodedPanel isEquivalentTo:panel]) {
				return panel;
				/// We don't delete decodedPanel now because it would prevent replacing the genotypes' markers by their equivalent in the replacement panel (see below).
			}
		}
		[self.importedRootPanels addObject:decodedPanel.topAncestor];
		
	} else if([object isKindOfClass:Chromatogram.class]) {
		Chromatogram *decodedSample = (Chromatogram *)object;
		Panel *samplePanel = decodedSample.panel;
		for(Genotype *genotype in decodedSample.genotypes) {
			if(genotype.marker.panel == samplePanel) {
				/// The panel has not been replaced.
				break;
			}
			/// If the decoded panel has been replaced by one already in the database,
			/// we rewire the markers of the sample's genotypes to equivalent markers in the replacement panel.
			for(Mmarker *marker in samplePanel.markers) {
				if([genotype.marker isEquivalentTo:marker]) {
					[genotype managedObjectOriginal_setMarker:marker];
					break;
				}
			}
		}
		/// to keep track of the progress, we use a decoded sample as a unit of work
		totalSamplesProcessed++;
		if(totalSamplesProcessed % 100 == 0) {		/// we report every 100 samples decoded
			self.importProgress.completedUnitCount = totalSamplesProcessed;
			self.importProgress.localizedDescription = [NSString stringWithFormat:@"%ld samples decoded", totalSamplesProcessed];
		}
	} else if([object class] == SizeStandard.class) {
		/// like for Panels, we return an equivalent size standard already in the database, if any
		SizeStandard *decodedSizeStandard = (SizeStandard *)object;
		NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:SizeStandard.entity.name];
		NSArray *sizeStandards = [decodedSizeStandard.managedObjectContext executeFetchRequest:request error:nil];
		for(SizeStandard *standard in sizeStandards) {
			if(standard != decodedSizeStandard && [decodedSizeStandard isEquivalentTo:standard]) {
				[decodedSizeStandard.managedObjectContext deleteObject:decodedSizeStandard];
				return standard;
			}
		}
		
		/// if the size standard is not replaced, we add a suffix to its name to make sure it is unique and to signify that is was imported
		NSString *candidateName;
		int i = 1;
		while(true) {
			NSString *suffix = [NSString stringWithFormat:@" %d",i];
			if(i == 1) {
				suffix = @"";
			}
			candidateName =[NSString stringWithFormat:@"%@ -imported%@", decodedSizeStandard.name, suffix];
			NSArray *sameNameStandards = [sizeStandards filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", candidateName]];
			if(sameNameStandards.count == 0) {
				break;
			}
			i++;
		}
		decodedSizeStandard.name = candidateName;
	}
	
	return object;
}


- (void)unarchiverDidFinish:(NSKeyedUnarchiver *)unarchiver {
	/// we remove top ancestors of imported panels that were not retained (replaced by existing panels)
	[self.rootFolderPanels minusSet:self.importedRootPanels];
	for(Folder *folder in self.rootFolderPanels) {
		[folder.managedObjectContext deleteObject:folder];
	}
	[self.rootFolderPanels removeAllObjects];
}


- (NSMutableSet *)importedRootPanels {
	if(!_importedRootPanels) {
		_importedRootPanels = NSMutableSet.new;
	}
	return _importedRootPanels;
}


- (NSMutableSet *)rootFolderPanels {
	if(!_rootFolderPanels) {
		_rootFolderPanels = NSMutableSet.new;
	}
	return _rootFolderPanels;
}


@end
