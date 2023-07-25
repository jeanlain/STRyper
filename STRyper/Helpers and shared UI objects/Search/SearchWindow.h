//
//  SearchWindow.h
//  STRyper
//
//  Created by Jean Peccoud on 26/02/2023.
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



#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN


/// A window showing a predicate editor to configure a search and to be used as a modal sheet.
///
/// The window has a text field showing a message on top, a predicate editor, a checkbox specifying whether the search is case sensitive, an ok button and a cancel button.
///
/// The predicate editor is not embedded in a scrollview. It is assumed that the number of rows will never be so large as to require scrolling.
///
/// This class does not allow changing the predicate editor, nor using a subclass of `NSPredicateEditor` (which is an area of improvement).
/// The predicate editor must be given relevant row templates and a predicate before the window is shown.
/// The predicate editor is simple, and case sensitivity is applied to all subpredicates (if the predicate is a compound predicate).
@interface SearchWindow : NSWindow

/// Returns a new search window from a nib file in the main bundle.
+(nullable instancetype)searchWindow;

/// The predicate editor of the search window.
@property (weak, nonatomic, readonly) NSPredicateEditor *predicateEditor;

/// The check box allowing to control the case sensitivity of the predicate.
///
/// If the check box is ticked, the predicate returned by ``predicate`` will only contain case-insensitive search terms.
@property (weak, nonatomic, readonly) NSButton *caseSensitiveOptionCheckBox;

/// The predicate to specify or to retrieve from the predicate editor.
///
/// One should use this property rather than the objectValue of the ``predicateEditor`` to take into account the state the ``caseSensitiveOptionCheckBox``.
///
/// If the predicate contains at least one case insensitive search term, the ``caseSensitiveOptionCheckBox`` indicating case sensitivity will be checked.
@property (nonatomic) NSPredicate *predicate;

/// The message to show in the text field on top of the search window.
@property (nonatomic, copy) NSString *message;


@end

NS_ASSUME_NONNULL_END
