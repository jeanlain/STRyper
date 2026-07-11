//
//  InfoOutlineView.m
//  STRyper
//
//  Created by Jean Peccoud on 28/09/2025.
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

#import "InfoOutlineView.h"

@implementation InfoOutlineView

- (void)drawGridInClipRect:(NSRect)clipRect {
	if(!self.drawGridForMainSectionsOnly) {
		[super drawGridInClipRect:clipRect];
	}
	/// The grid is not drawn where there are no row views. 
}


/// Returns an image for a row.
///
/// This method workarounds the fact that `tableView dragImageForRowsWithIndexes` does not
/// renders subviews of rows that are not `NSTableRowView` instances.
/// - Parameter row: The index of the row
- (NSImage *)imageForRow:(NSInteger)row {
	NSTableRowView *rowView = [self rowViewAtRow:row makeIfNecessary:NO];
	if (!rowView) {
		return nil;
	}

	NSRect bounds = rowView.bounds;
	NSBitmapImageRep *rep = [rowView bitmapImageRepForCachingDisplayInRect:bounds];

	[rowView cacheDisplayInRect:bounds toBitmapImageRep:rep];
	NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
	[image addRepresentation:rep];

	return image;
}


- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows tableColumns:(NSArray<NSTableColumn *> *)tableColumns event:(NSEvent *)dragEvent offset:(NSPointPointer)dragImageOffset {
	
	/// When a section is being dragged, we make as if its subsection (child row) is too.
	NSMutableIndexSet *draggedRows = dragRows.mutableCopy;
	[dragRows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
		id item = [self itemAtRow:row];
		id mainSection = [self parentForItem:item];
		if(!mainSection) { /// A main section is being dragged
			mainSection = item;
		}
		NSInteger parentRow = [self rowForItem:mainSection];
		NSInteger nRows = self.numberOfRows;
		for (NSInteger childRow = parentRow+1; childRow < nRows; childRow++) {
			id child = [self itemAtRow:childRow];
			if([self parentForItem:child] == mainSection) {
				[draggedRows addIndex:childRow];
			}
		}
	}];
	
	/// We generate the drag image by stacking images of rows being dragged.
	NSMutableArray<NSImage *> *rowImages = NSMutableArray.new;
	__block CGFloat totalHeight = 0.0;
	__block CGFloat maxWidth = 0.0;

	[draggedRows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
		NSImage *rowImage = [self imageForRow:row];
		if (rowImage) {
			[rowImages addObject:rowImage];
			totalHeight += rowImage.size.height;
			maxWidth = MAX(maxWidth, rowImage.size.width);
		}
	}];

	NSImage *finalImage = [[NSImage alloc] initWithSize:NSMakeSize(maxWidth, totalHeight)];

	[finalImage lockFocus];
	CGFloat y = totalHeight;
	for (NSImage *img in rowImages) {
		y -= img.size.height;
		[img drawAtPoint:NSMakePoint(0.0, y) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
	}
	[finalImage unlockFocus];

	if (dragImageOffset) {
		*dragImageOffset = NSZeroPoint;
	}

	return finalImage;
}


@end
