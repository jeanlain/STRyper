//
//  TraceOutlineViewPrinter.m
//  STRyper
//
//  Created by Jean Peccoud on 08/07/2025.
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


#import "TraceOutlineViewPrinter.h"


@implementation TraceOutlineViewPrinter {
	TraceOutlineView *traceOutlineView; /// The outline view that is printed.
	NSRect *rowRects;	   /// The rectangles in which row views will be drawn in the printer coordinates.
	NSMutableArray<NSValue *> *pageRects;	/// The rectangles represented by each printed page in the printer coordinates.
	NSInteger rowCount;	   /// Number of rows in the view to print.
	NSInteger pageCount;   /// Number of pages to print.
	CGFloat scalingFactor;   /// Scaling factor of the current print operation.
}



-(instancetype) initWithView:(TraceOutlineView *)traceOutlineView {
	NSRect frame = traceOutlineView.bounds;
	frame.size.width = traceOutlineView.visibleRect.size.width;
	
	self = [super initWithFrame:frame];
	if(self) {
		self->traceOutlineView = traceOutlineView;
	}
	return self;
}


- (BOOL)isFlipped {
	return YES;
}



- (NSRect)rectForPage:(NSInteger)page {
	if(page <= pageRects.count && page >= 1) {
		NSRect rect = pageRects[page-1].rectValue;
		return rect;
	}
	return NSZeroRect;
}


- (BOOL)knowsPageRange:(NSRangePointer)range {
	CGFloat printHeight = [self printHeightForCurrentOperation];
	CGFloat pageWidth = [self printWidthForCurrentOperation];
	if(rowRects) {
		free(rowRects);
	}
	rowCount = traceOutlineView.numberOfRows;
	rowRects = calloc(rowCount, sizeof(NSRect));
	pageRects = NSMutableArray.new; /// Since the number or page is not pre-computed, it's easier to use a mutable array than a C array.
	
	CGFloat currentRowBottom = 0; /// Rows are created from top to bottom. This is the
								  /// Y position of the last row in the view (the view's top is at Y = 0).
	CGFloat currentPageTop = 0;	  /// The Y position of the top edge of the current page in the view.
	
	CGFloat tableWidth = traceOutlineView.visibleRect.size.width;
	CGFloat previousHeight = 0;
	for (int i = 0; i < rowCount; i++) {
		NSRect rowRect = [traceOutlineView rectOfRow:i];
		CGFloat rowHeight = rowRect.size.height*scalingFactor;
		rowRect = NSMakeRect(0, currentRowBottom, tableWidth*scalingFactor, rowHeight);
		rowRects[i] = rowRect;
		currentRowBottom = NSMaxY(rowRect);
		
		CGFloat mergedHeight = rowHeight; /// We combine the row with a previous one if it is a thin one
		if(i > 0 && rowHeight/scalingFactor >= 39) {
			if(previousHeight/scalingFactor <= 21) {
				mergedHeight += previousHeight;
			}
		}
		
		previousHeight = rowHeight;
		int nPagesUsed = (currentRowBottom - currentPageTop)/printHeight; /// Number of pages used by the row.
		for (int p = 0; p < nPagesUsed; p++) {
			/// We move the row to the next page if its height does not exceed the page height (to avoid tiling rows across pages)
			/// The height of the current printed page will be reduced in this case.
			CGFloat pageHeight = mergedHeight > printHeight? printHeight : currentRowBottom - currentPageTop - mergedHeight;
			NSRect pageRect = NSMakeRect(0, currentPageTop, pageWidth, pageHeight);
			[pageRects addObject:[NSValue valueWithRect:pageRect]];
			currentPageTop = NSMaxY(pageRect);
		}
	}
	/// We define the rectangle for the last page
	NSRect pageRect = NSMakeRect(0, currentPageTop, pageWidth, currentRowBottom - currentPageTop);
	[pageRects addObject:[NSValue valueWithRect:pageRect]];
	
	range->location = 1;
	range->length = pageRects.count;
	
	[self setFrameSize:NSMakeSize(tableWidth, currentRowBottom)];
	
	return YES;
}


- (CGFloat)printHeightForCurrentOperation {
	/// Obtain the print info object for the current operation
	NSPrintInfo *pi = NSPrintOperation.currentOperation.printInfo;
	
	/// Calculate the page height in points
	NSSize paperSize = pi.paperSize;
	CGFloat pageHeight = paperSize.height - pi.topMargin - pi.bottomMargin;
	
	/// Convert height to the scaled view
	scalingFactor = pi.scalingFactor;
	return pageHeight;
}


- (CGFloat)printWidthForCurrentOperation {
	/// Obtain the print info object for the current operation
	NSPrintInfo *pi = NSPrintOperation.currentOperation.printInfo;
	
	/// Calculate the page width in points
	NSSize paperSize = pi.paperSize;
	return paperSize.width - pi.leftMargin - pi.rightMargin;
}


- (void)drawRect:(NSRect)dirtyRect {
	/// We draw row view in the rectangles we defined.
	if(rowRects) {
		NSGraphicsContext *context = NSGraphicsContext.currentContext;
		
		for (int i = 0; i < rowCount; i++) {
			NSRect rowRect = rowRects[i];
			id item = [traceOutlineView itemAtRow:i];
			if(NSIntersectsRect(dirtyRect, rowRect) && item) {
				/// We compute the visible rectangle of the row view in print (It may be clipped depending on the scale factor)
				NSRect visibleRowRect = NSIntersectionRect(rowRect, dirtyRect);
				CGFloat leftCrop = visibleRowRect.origin.x - rowRect.origin.x;
				CGFloat bottomCrop = visibleRowRect.origin.y - rowRect.origin.y;
				NSRect rowViewVisibleRect = NSMakeRect(leftCrop/scalingFactor, bottomCrop/scalingFactor,
													   visibleRowRect.size.width/scalingFactor,
													   visibleRowRect.size.height/scalingFactor);
				
				@autoreleasepool {
					NSView *rowView = [traceOutlineView.delegate outlineView:traceOutlineView printableRowViewForItem:item clipToVisibleWidth:YES];
					if(rowView) {
						[self drawRect: rowViewVisibleRect ofRowView:rowView intoRect:visibleRowRect context:context];
					}
				}
			}
		}
	}
}


- (void)drawRect:(NSRect)sourceRect ofRowView:(NSView *)rowView intoRect:(NSRect)destRect context:(NSGraphicsContext *)context {
	[NSGraphicsContext saveGraphicsState];
	
	CGContextRef cgContext = context.CGContext;
	
	/// Compute scale factors to fit source into destination
	CGFloat scaleX = destRect.size.width  / sourceRect.size.width;
	CGFloat scaleY = destRect.size.height / sourceRect.size.height;
	
	/// Translate to destination origin
	CGContextTranslateCTM(cgContext, destRect.origin.x, destRect.origin.y);
	
	/// Scale to match sourceRect size
	CGContextScaleCTM(cgContext, scaleX, scaleY);
	
	/// Translate coordinate space so sourceRect.origin maps to (0, 0)
	CGContextTranslateCTM(cgContext, -sourceRect.origin.x, -sourceRect.origin.y);
	
	/// Clip to the portion being drawn
	CGContextClipToRect(cgContext, sourceRect);
	
	/// Draw only the sourceRect portion
	[rowView displayRectIgnoringOpacity:sourceRect inContext:context];
	
	[NSGraphicsContext restoreGraphicsState];
}


- (void)dealloc {
	if(rowRects) {
		free(rowRects);
	}
}

@end
