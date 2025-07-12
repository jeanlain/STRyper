//
//  TraceViewTablePrinter.m
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


#import "TraceViewTablePrinter.h"
#import "LabelView.h"


@implementation TraceViewTablePrinter {
	NSOutlineView *traceOutlineView; /// The outline view that is printed.
	id<NSOutlineViewDelegate> tableDelegate;	/// Its delegate and datasource objects.
	id<NSOutlineViewDataSource> tableDataSource;
	NSMutableArray *items; /// The items represented by the rows of this outline view
	CGFloat *rowHeights;   /// Heights of rows of the outline view.
	NSRect *rowRects;	   /// The rectangles in which row views will be drawn in our coordinates.
	NSMutableArray<NSValue *> *pageRects;	/// The rectangles represented by each printed page in our coordinates.
	CGFloat tableWidth;	   /// The with of the outline view to print.
	NSInteger rowCount;	   /// Number of rows in the view to print.
	NSInteger pageCount;   /// Number of pages to print.
	float scalingFactor;   /// Scaling factor of the current print operation.
}



- (instancetype)initWithTable:(NSOutlineView *)traceTable {
	self = [super initWithFrame:traceTable.bounds];
	if(self && traceTable.delegate && traceTable.dataSource) {
		traceOutlineView = traceTable;
		tableDelegate = traceTable.delegate;
		tableDataSource = traceTable.dataSource;
		rowCount = traceTable.numberOfRows;
		tableWidth = traceTable.bounds.size.width;
		if(rowHeights) {
			free(rowHeights);
		}
		rowHeights = calloc(rowCount, sizeof(CGFloat));
		items = [NSMutableArray arrayWithCapacity:rowCount];
		for (int i = 0; i < rowCount; i++) {
			id item = [traceTable itemAtRow:i];
			if(item) {
				[items addObject:item];
				rowHeights[i] = [tableDelegate outlineView:traceTable heightOfRowByItem:item];
			}
		}
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
	float printHeight = [self printHeightForCurrentOperation];
	float pageWidth = [self printWidthForCurrentOperation];
	if(rowRects) {
		free(rowRects);
	}
	rowRects = calloc(rowCount, sizeof(NSRect));
	pageRects = NSMutableArray.new; /// Since the number or page is not pre-computed, it's easier to use a mutable array than a C array.
	
	float currentRowBottom = 0; /// Rows are created from top to bottom. This is the
								/// Y position of the last row in the view (whose top is at Y = 0).
	float currentPageTop = 0;	/// The Y position fo the top edge of the current page in the view.
	
	for (int i = 0; i < rowCount; i++) {
		CGFloat rowHeight = rowHeights[i]*scalingFactor;
		NSRect rowRect = NSMakeRect(0, currentRowBottom, tableWidth*scalingFactor, rowHeight);
		rowRects[i] = rowRect;
		currentRowBottom = NSMaxY(rowRect);
		
		float mergedHeight = rowHeight; /// We may combine the row with a previous one if it is a thin one
		if(i > 0 && rowHeight >= 40) {
			float previousHeight = rowHeights[i-1];
			if(previousHeight <= 20) {
				mergedHeight += previousHeight*scalingFactor;
			}
		}
		int nPagesUsed = (currentRowBottom - currentPageTop)/printHeight; /// Number of pages used by the row.
		for (int p = 0; p < nPagesUsed; p++) {
			/// We the row will be on the next page if its height does not exceed the page height (to avoid tiling rows across pages)
			/// The height of the current printed page will be reduced in this case.
			float pageHeight = rowHeight > printHeight? printHeight : currentRowBottom - currentPageTop - mergedHeight;
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
	float pageHeight = paperSize.height - pi.topMargin - pi.bottomMargin;
	
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
			if(NSIntersectsRect(dirtyRect, rowRect)) {
				if(i < items.count) {
					/// The bounds or the corresponding row view (without scaling)
					NSRect rowViewFrame = NSMakeRect(0, 0, rowRect.size.width/scalingFactor, rowRect.size.height/scalingFactor);
										
					/// We compute the visible rectangle of the row view (It may be clipped depending on the scale factor)
					NSRect visibleRowRect = NSIntersectionRect(rowRect, dirtyRect);
					CGFloat leftCrop = visibleRowRect.origin.x - rowRect.origin.x;
					CGFloat bottomCrop = visibleRowRect.origin.y - rowRect.origin.y;
					NSRect rowViewVisibleRect = NSMakeRect(leftCrop/scalingFactor, bottomCrop/scalingFactor,
														 visibleRowRect.size.width/scalingFactor,
														 visibleRowRect.size.height/scalingFactor);
					
					NSView *rowView = [self printableRowViewForItem:items[i] withFrame:rowViewFrame];
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



-(NSTableRowView *) printableRowViewForItem:(id) item withFrame:(NSRect)frame {
	if(!tableDelegate || !tableDataSource) {
		return nil;
	}
	NSOutlineView *outlineView; /// To avoid a warning if we use `nil` instead in the delegate method calls. 
	NSTableRowView *rowView = [tableDelegate outlineView: outlineView rowViewForItem:item];
	if(!rowView) {
		rowView = NSTableRowView.new;
		rowView.frame = frame;
	}

	float currentX = 0; /// The X position of the last table cell view added to the row view.
	for(NSTableColumn *column in traceOutlineView.tableColumns) {
		if(!column.isHidden) {
			NSView *cellView = [tableDelegate outlineView:outlineView viewForTableColumn:column item:item];
			if(cellView) {
				if([cellView respondsToSelector:@selector(setObjectValue:)]) {
					id object = [tableDataSource outlineView:outlineView objectValueForTableColumn:column byItem:item];
					[(id) cellView setObjectValue:object];
				}
				cellView.frame = NSMakeRect(currentX, 0, column.width, frame.size.height);
				[rowView addSubview:cellView];
				currentX = NSMaxX(cellView.frame);
			}
		}
	}
	
	/// We make the row view ready for printing.
	NSArray *subViews = [self.class allSubviewsOf:rowView];
	for(NSView *subView in subViews) {
		/// We make the subview as white as possible.
		[subView setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
		if([subView respondsToSelector:@selector(setBackgroundColor:)]) {
			[(id)subView setBackgroundColor:NSColor.whiteColor];
		}
		
		if([subView isKindOfClass:NSButton.class]) {
			subView.hidden = YES; /// We don't print buttons.
		} else if([subView isKindOfClass:LabelView.class]) {
				subView.wantsLayer = NO; /// So these views will use drawRect when printed.
		} else if([subView isKindOfClass:NSScrollView.class]) {
			/// We hide scrollers in print, especially of they overlap contents
			NSScrollView *scrollView = (NSScrollView *)subView;
			CGFloat scrollerHeight = scrollView.horizontalScroller.frame.size.height;
			CGFloat scrollerWidth = scrollView.verticalScroller.frame.size.width;
			scrollView.hasVerticalScroller = NO;
			scrollView.hasHorizontalScroller = NO;
			if(scrollView.scrollerStyle == NSScrollerStyleLegacy) {
				/// We need to resize the clip view "manually" as appkit does not yet know that scroller are removed
				NSClipView *clipView = scrollView.contentView;
				NSRect clipViewFrame = clipView.frame;
				clipViewFrame.size.height += scrollerHeight; /// This"overshoots" the desired frame size, but appkit
															 /// will subtract the scroller thickness in setFrame.
				clipViewFrame.size.width += scrollerWidth;
				clipView.frame = clipViewFrame;
				[scrollView layoutSubtreeIfNeeded]; 		/// required
				[scrollView tile];

			}
		}
	}
	
	return rowView;
}



/// Returns all subviews of a view, recursively.
/// - Parameter view: a view.
+ (NSArray *)allSubviewsOf:(NSView *)view {
	/// We could have made this a category of `NSView`, but this method is only used here.
	NSMutableArray *allSubviews = [NSMutableArray arrayWithObject:view];
	NSArray *subviews = view.subviews;
	for (NSView *view in subviews) {
		[allSubviews addObjectsFromArray:[self allSubviewsOf:view]];
	}
	return allSubviews.copy;
}


- (void)dealloc {
	if(rowHeights) {
		free(rowHeights);
	}
	if(rowRects) {
		free(rowRects);
	}
}

@end
