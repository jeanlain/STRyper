//
//  IndexImageView.m
//  STRyper
//
//  Created by Jean Peccoud on 02/04/2023.
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



#import "IndexImageView.h"

NSBindingName const ImageIndexBinding = @"imageIndex";

@implementation IndexImageView

- (void)setImageArray:(NSArray<NSImage *> *)imageArray {
	_imageArray = [NSArray arrayWithArray:imageArray];
	NSInteger index = self.imageIndex;
	if(index >= 0 && index < _imageArray.count) {
		NSImage *image = _imageArray[index];
		if([image isKindOfClass:NSImage.class]) {
			self.image = image;
		} else {
			self.image = nil;
		}
	} else {
		self.image = nil;
	}
}


- (void)setImageIndex:(NSInteger) imageIndex {
	_imageIndex = imageIndex;
	NSArray *imageArray = self.imageArray;
	if(imageIndex < 0 || imageIndex >= imageArray.count) {
		self.image = nil;
	} else {
		NSImage *image = imageArray[imageIndex];
		if([image isKindOfClass:NSImage.class]) {
			self.image = image;
		} else {
			self.image = nil;
		}
	}
}





@end
