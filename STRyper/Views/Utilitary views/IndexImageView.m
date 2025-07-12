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
	_imageArray = imageArray.copy;
	NSUInteger index = self.imageIndex;
	if(index >= 0 && index < _imageArray.count) {
		NSImage *image = _imageArray[index];
		if([image isKindOfClass:NSImage.class]) {
			super.image = image;
		} else {
			NSLog(@"%@ %@ element %ld of the image array is not an NSImage instance", self.description, NSStringFromSelector(_cmd), index);
			super.image = nil;
		}
	} else {
		NSLog(@"%@ %@ image index %ld exceeds the receiver's imageArray count (%ld)", self.description, NSStringFromSelector(_cmd), index, _imageArray.count);
		super.image = nil;
	}
}


- (void)setImageIndex:(NSUInteger) imageIndex {
	_imageIndex = imageIndex;
	NSArray *imageArray = self.imageArray;
	if(imageArray) {
		if(imageIndex >= imageArray.count) {
			NSLog(@"%@ %@ image index %ld exceeds the receiver's imageArray count (%ld)", self.description, NSStringFromSelector(_cmd), imageIndex, _imageArray.count);
			super.image = nil;
		} else {
			NSImage *image = imageArray[imageIndex];
			if([image isKindOfClass:NSImage.class]) {
				super.image = image;
			} else {
				NSLog(@"%@ %@ element %ld of the image array is not an NSImage instance", self.description, NSStringFromSelector(_cmd), imageIndex);
				super.image = nil;
			}
		}
	}
}



- (void)setNilValueForKey:(NSString *)key {
	if([key isEqualToString:@"imageIndex"]) {
		[self setValue:[NSNumber numberWithInt:0] forKey:key];
	} else {
		[super setNilValueForKey:key];
	}
	
}


- (void)setImage:(NSImage *)image {
	NSUInteger index = [_imageArray indexOfObjectIdenticalTo:image];
	if(!_imageArray || index == NSNotFound) {
		NSLog(@"%@ %@ image is not part of the receiver's imageArray", self.description, NSStringFromSelector(_cmd));
	} else {
		self.imageIndex = index;
	}
}


@end
