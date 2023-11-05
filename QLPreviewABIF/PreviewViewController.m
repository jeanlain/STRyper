//
//  PreviewViewController.m
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import "PreviewViewController.h"
#import <Quartz/Quartz.h>
#import "ABIFparser.h"
#import "TracePreviewView.h"

@interface PreviewViewController () <QLPreviewingController>

@property (nonatomic) NSString *sampleInformation;
    
@end

/// Keys corresponding to the sample information shown;
static NSString *sampleNameKey = @"sampleName",
*wellKey = @"well",
*plateNameKey = @"plateName";


@implementation PreviewViewController {
	__weak TracePreviewView *traceView;
}


- (NSString *)nibName {
    return @"PreviewViewController";
}


static NSDictionary *itemsToImport, *itemFieldNames;

+(void)initialize {
	itemsToImport =
	///the items that we import from an ABIF file. keys = item name combined with item number (as per ABIF specs). Value = corresponding attribute names of Chromatogram, except for some which are attributes of Trace
	@{
		@"CTNM1": plateNameKey,
		
		/// raw fluorescence data and dye names, not attributes of Chromatogram, but of Trace
		@"DATA1": @"rawData1",
		@"DATA2": @"rawData2",
		@"DATA3": @"rawData3",
		@"DATA4": @"rawData4",
		@"DATA105": @"rawData5",
		@"RUND2": @"runStopDate",
		@"RUNT2": @"runStopTime",
		@"TUBE1": wellKey,
		@"SCAN1": @"nScans",
		@"SpNm1": sampleNameKey
	};
	
	itemFieldNames =
	@{
		sampleNameKey : @"Sample name",
		plateNameKey : @"Plate name",
		wellKey : @"Well"
	};
	
}

- (void)loadView {
    [super loadView];
	traceView = [self.view viewWithTag:99];
}

/*
 * Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.
 *
- (void)preparePreviewOfSearchableItemWithIdentifier:(NSString *)identifier queryString:(NSString *)queryString completionHandler:(void (^)(NSError * _Nullable))handler {
    
    // Perform any setup necessary in order to prepare the view.
    
    // Call the completion handler so Quick Look knows that the preview is fully loaded.
    // Quick Look will display a loading spinner while the completion handler is not called.

    handler(nil);
}
*/

- (void)preparePreviewOfFileAtURL:(NSURL *)url completionHandler:(void (^)(NSError * _Nullable))handler {
	NSError *error;
	NSDictionary *sample = [ABIFparser dictionaryWithABIFile:url.path itemsToImport:itemsToImport error:&error];
		
	if(!error) {
		NSMutableArray *traces = [NSMutableArray arrayWithCapacity:5];
		for (int i = 1; i <= 5; i++) {
			NSData *trace = sample[[@"rawData" stringByAppendingFormat:@"%d", i]];
			if(trace) {
				[traces addObject:trace];
			}
		}
		
		NSMutableArray *strings = [NSMutableArray arrayWithCapacity:3];
		for(NSString *key in @[sampleNameKey, plateNameKey, wellKey]) {
			NSString *value = sample[key];
			if([value isKindOfClass:NSString.class] && value.length > 0) {
				NSString *fieldName = itemFieldNames[key];
				if(fieldName) {
					[strings addObject:[NSString stringWithFormat:@"%@: %@", fieldName, value]];
				}
			}
		}
		
		if(strings.count > 0) {
			self.sampleInformation = [strings componentsJoinedByString:@"   "];
		} else {
			self.sampleInformation = @"Sample information missing";
		}
		
		traceView.traces = [NSArray arrayWithArray:traces];
	}
	handler(error);
	
}

@end

