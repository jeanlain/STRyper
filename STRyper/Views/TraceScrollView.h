//
//  TraceScrollView.h
//  STRyper
//
//  Created by Jean Peccoud on 14/12/12.
//  Copyright (c) 2012 Jean Peccoud. All rights reserved.
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



@import Cocoa;

/// A scrollview designed to have a ``TraceView`` object as its document view.
///
/// A `TraceScrollView` overrides `NSResponder` methods to allow the user to zoom the trace view with usual gestures and alt-scroll,
/// and to move between markers shown by the ``MarkerView`` via swipe.
///
/// It passes the scrolling event to the next responder when the user scrolls mostly vertically, as it should only scroll horizontally.
/// For the same reason, a `TraceScrollView` does not have a vertical scroller by default.
///
/// Instances of this class enforce the legacy scroller style, otherwise, the horizontal scroller would overlap with the curves shown by the document view.
///
/// A `TraceScrollView` creates a ``VScaleView``  when it sets its document view, if this document view is a ``TraceView``.
///
@interface TraceScrollView : NSScrollView 

/// Whether the user can move between markers using a horizontal scroll gesture.
@property (nonatomic) BOOL allowSwipeBetweenMarkers;

extern const NSBindingName AllowSwipeBetweenMarkersBinding;

/// Whether the scroll view always shows its horizontal scroller, irrespective of the system preference.
///
/// If `YES`, this property enforce the legacy scroller style.
@property (nonatomic) BOOL alwaysShowsScroller;
extern const NSBindingName AlwaysShowsScrollerBinding;


@end
