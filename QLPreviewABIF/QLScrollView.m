//
//  QLScrollView.m
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 05/11/2023.
//

#import "QLScrollView.h"

@implementation QLScrollView


- (void)scrollClipView:(NSClipView *)clipView toPoint:(NSPoint)point {
	if(self.documentView.clipsToBounds) {
		[super scrollClipView:clipView toPoint:point];
	}
}


@end
