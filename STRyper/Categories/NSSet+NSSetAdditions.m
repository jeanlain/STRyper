//
//  NSSet+NSSetAdditions.m
//  STRyper
//
//  Created by Jean Peccoud on 29/05/2023.
//
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


#import "NSSet+NSSetAdditions.h"

@implementation NSSet (NSSetAdditions)

- (BOOL)hasObject:(id)object {
	for(id obj in self) {
		if(obj == object) {
			return YES;
		}
	}
	return NO;
}

@end
