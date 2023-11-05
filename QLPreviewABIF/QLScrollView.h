//
//  QLScrollView.h
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 05/11/2023.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A scroll view that does not scroll under a certain condition.
///
/// The view will not scroll if its document view results NO to `clipsToBounds`.
/// This is only design to work if the document view is a ``TracePreviewView``,
/// which returns no to this message while it is being resized.
/// This is because appkit sometime sees fit to scroll the document view when it is resized, which produces unwanted behavior.
@interface QLScrollView : NSScrollView

@end

NS_ASSUME_NONNULL_END
