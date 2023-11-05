//
//  TracePreviewView.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 04/11/2023.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A view that shows traces of a chromatogram in a quick look window.
///
/// This duplicates drawing methods of  TraceView.
@interface TracePreviewView : NSView

/// The traces data that the view plots.
@property (nonatomic) NSArray<NSData *> *traces;

@end

NS_ASSUME_NONNULL_END
