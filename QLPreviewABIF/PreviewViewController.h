//
//  PreviewViewController.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import <Cocoa/Cocoa.h>

/// The object that controls the quick look preview.
@interface PreviewViewController : NSViewController

/// The information shown about a sample on top of the preview pane.
///
/// This property is bound to the value of a text field, which shows sample name, plate name and well, if available.
@property (nonatomic, readonly) NSString *sampleInformation;

@end
