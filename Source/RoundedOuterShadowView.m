/**
 * Copyright (c) 2008, 2014, Pecunia Project. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; version 2 of the
 * License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301  USA
 */

#import "RoundedOuterShadowView.h"
#import "GraphicsAdditions.h"

@implementation RoundedOuterShadowView

@synthesize leftMargin;
@synthesize rightMargin;
@synthesize topMargin;
@synthesize bottomMargin;

- (void)awakeFromNib {
    leftMargin = 10;
    rightMargin = 10;
    topMargin = 10;
    bottomMargin = 10;
}


// Shared objects.
static NSShadow *borderShadow = nil;

- (void)drawRect: (NSRect)rect
{
    [NSGraphicsContext saveGraphicsState];

    // Initialize shared objects.
    if (borderShadow == nil) {
        borderShadow = [[NSShadow alloc] initWithColor: [NSColor colorWithDeviceWhite: 0 alpha: 0.5]
                                                offset: NSMakeSize(1, -1)
                                            blurRadius: 5.0];
    }

    // Outer bounds with shadow.
    NSRect bounds = [self bounds];
    bounds.size.width -= leftMargin + rightMargin;
    bounds.size.height -= topMargin + bottomMargin;
    bounds.origin.x += leftMargin;
    bounds.origin.y += bottomMargin;

    NSBezierPath *borderPath = [NSBezierPath bezierPathWithRoundedRect: bounds xRadius: 5 yRadius: 5];
    [borderShadow set];
    [[NSColor whiteColor] set];
    [borderPath fill];

    [NSGraphicsContext restoreGraphicsState];
}

- (void)resizeWithOldSuperviewSize: (NSSize)oldSize
{
    [super resizeWithOldSuperviewSize: oldSize];

    // Ensure the given minimum size. Take also margins into account, so we do not go below what we need for them.
    CGSize size = self.frame.size;
    CGFloat minWidth = self.minimumSize.width;
    if (minWidth < leftMargin + rightMargin) {
        minWidth = leftMargin + rightMargin;
    }
    CGFloat minHeight = self.minimumSize.height;
    if (minHeight < bottomMargin + topMargin) {
        minHeight = bottomMargin + topMargin;
    }
    if (size.width < minWidth) {
        size.width = minWidth;
    }
    if (size.height < minHeight) {
        size.height = minHeight;
    }
    [self setFrameSize: size];
}

@end
