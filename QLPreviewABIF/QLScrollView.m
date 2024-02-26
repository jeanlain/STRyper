//
//  QLScrollView.m
//  QLPreviewABIF
//
//  Created by Jean Peccoud on 05/11/2023.
//
//  Created by Jean Peccoud on 28/03/2022.
//  Copyright © 2022 Jean Peccoud. All rights reserved.
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



#import "QLScrollView.h"

@implementation QLScrollView


- (void)scrollClipView:(NSClipView *)clipView toPoint:(NSPoint)point {
	if(self.documentView.clipsToBounds) {
		[super scrollClipView:clipView toPoint:point];
	}
}


@end
