//
//  TableHeaderView.m
//  STRyper
//
//  Created by Jean Peccoud on 11/10/2022.
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



#import "TableHeaderView.h"

@implementation TableHeaderView

- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)object {
	if(NSIntersectsRect(rect, self.visibleRect)) {
		[super addCursorRect:rect cursor:object];
	}
}



@end
