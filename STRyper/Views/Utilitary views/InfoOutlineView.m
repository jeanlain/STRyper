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

@end
