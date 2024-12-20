# AdMoai iOS SDK Demo App

This demo app showcases the AdMoai iOS SDK's capabilities and provides example implementations of various ad formats. The app connects to a mock ad server for demonstration purposes.

## Running the Demo

1. Open `Demo.xcodeproj`
2. Select your target device/simulator
3. Build and run

The demo app includes examples of:

- Different ad layouts
- Targeting options
- User consent management
- Data collection controls
- Request/response inspection

## Mock Server

For development and testing, the example app uses the mock decision engine server at `https://mock.api.admoai.com`. This server returns predictable responses based on the placement and template combinations.

### Available Placements

<table>
    <tr>
        <th>Placement</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><code>search</code></td>
        <td>Search results with image and text</td>
    </tr>
    <tr>
        <td><code>vehicleSelection</code></td>
        <td>Vehicle selection interface</td>
    </tr>
    <tr>
        <td><code>home</code></td>
        <td>Home screen with companion</td>
    </tr>
    <tr>
        <td><code>menu</code></td>
        <td>Text-only menu</td>
    </tr>
    <tr>
        <td><code>promotions</code></td>
        <td>Promotional carousel</td>
    </tr>
    <tr>
        <td><code>waiting</code></td>
        <td>Waiting for start process</td>
    </tr>
    <tr>
        <td><code>rideSummary</code></td>
        <td>Ride summary with details</td>
    </tr>
</table>

### Available Templates

<table>
    <tr>
        <th>Template</th>
        <th>Styles</th>
        <th>Field</th>
        <th>Type</th>
        <th>Description</th>
        <th>Example</th>
        <th>Events</th>
    </tr>
    <tr>
        <td rowspan="3">
            <code>imageWithText</code>
        </td>
        <td rowspan="3">
            <code>imageLeft</code><br>
            <code>imageRight</code>
        </td>
        <td><code>squareImage</code></td>
        <td><code>image</code></td>
        <td>Square image for the search result</td>
        <td><code>https://example.com/product.jpg</code></td>
        <td rowspan="3">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td><code>clicks</code></td>
                    <td><code>default</code></td>
                </tr>
            </table>
        </td>
    </tr>
    <tr>
        <td><code>headline</code></td>
        <td><code>text</code></td>
        <td>Main text to display</td>
        <td><code>New Product Launch</code></td>
    </tr>
    <tr>
        <td><code>destinationURL</code></td>
        <td><code>url</code></td>
        <td>URL to navigate when clicked</td>
        <td><code>https://example.com/product</code></td>
    </tr>
    <tr>
        <td rowspan="2">
            <code>wideImageOnly</code>
        </td>
        <td rowspan="2">
            <code>default</code>
        </td>
        <td><code>wideImage</code></td>
        <td><code>image</code></td>
        <td>Full-width image</td>
        <td><code>https://example.com/banner.jpg</code></td>
        <td rowspan="2">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td><code>clicks</code></td>
                    <td><code>default</code></td>
                </tr>
            </table>
        </td>
    </tr>
    <tr>
        <td><code>destinationURL</code></td>
        <td><code>url</code></td>
        <td>URL to navigate when clicked</td>
        <td><code>https://example.com/offer</code></td>
    </tr>
    <tr>
        <td rowspan="9">
            <code>wideWithCompanion</code>
        </td>
        <td rowspan="9">
            <code>imageLeft</code><br>
            <code>imageRight</code><br>
            <code>wideImageOnly</code>
        </td>
        <td><code>squareImage</code></td>
        <td><code>image</code></td>
        <td>Square companion image</td>
        <td><code>https://example.com/companion.jpg</code></td>
        <td rowspan="9">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td><code>clicks</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td><code>custom</code></td>
                    <td><code>companionOpened</code></td>
                </tr>
            </table>
        </td>
    </tr>
    <tr>
        <td><code>wideImage</code></td>
        <td><code>image</code></td>
        <td>Wide banner image</td>
        <td><code>https://example.com/banner.jpg</code></td>
    </tr>
    <tr>
        <td><code>coverImage</code></td>
        <td><code>image</code></td>
        <td>Cover image</td>
        <td><code>https://example.com/cover.jpg</code></td>
    </tr>
    <tr>
        <td><code>headline</code></td>
        <td><code>text</code></td>
        <td>Headline text</td>
        <td><code>Welcome Back!</code></td>
    </tr>
    <tr>
        <td><code>body</code></td>
        <td><code>textarea</code></td>
        <td>Body text</td>
        <td><code>Discover our new features</code></td>
    </tr>
    <tr>
        <td><code>cta</code></td>
        <td><code>text</code></td>
        <td>Call to action text</td>
        <td><code>Learn More</code></td>
    </tr>
    <tr>
        <td><code>buttonColor</code></td>
        <td><code>color</code></td>
        <td>Button color</td>
        <td><code>#FF0000</code></td>
    </tr>
    <tr>
        <td><code>buttonTextColor</code></td>
        <td><code>color</code></td>
        <td>Button text color</td>
        <td><code>#FFFFFF</code></td>
    </tr>
    <tr>
        <td><code>clickThroughURL</code></td>
        <td><code>url</code></td>
        <td>URL to navigate</td>
        <td><code>https://example.com/home</code></td>
    </tr>
    <tr>
        <td rowspan="12">
            <code>carousel3Slides</code>
        </td>
        <td rowspan="12">
            <code>default</code>
        </td>
        <td><code>imageSlide1</code></td>
        <td><code>image</code></td>
        <td>First slide image</td>
        <td><code>https://example.com/promo1.jpg</code></td>
        <td rowspan="12">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td rowspan="3"><code>clicks</code></td>
                    <td><code>slide1</code></td>
                </tr>
                <tr>
                    <td><code>slide2</code></td>
                </tr>
                <tr>
                    <td><code>slide3</code></td>
                </tr>
            </table>
        </td>
    </tr>
    <tr>
        <td><code>headlineSlide1</code></td>
        <td><code>text</code></td>
        <td>First slide headline</td>
        <td><code>Special Offer!</code></td>
    </tr>
    <tr>
        <td><code>ctaSlide1</code></td>
        <td><code>text</code></td>
        <td>First slide call to action</td>
        <td><code>Get 20% Off</code></td>
    </tr>
    <tr>
        <td><code>URLSlide1</code></td>
        <td><code>url</code></td>
        <td>First slide navigation URL</td>
        <td><code>https://example.com/promo1</code></td>
    </tr>
    <tr>
        <td><code>imageSlide2</code></td>
        <td><code>image</code></td>
        <td>Second slide image</td>
        <td><code>https://example.com/promo2.jpg</code></td>
    </tr>
    <tr>
        <td><code>headlineSlide2</code></td>
        <td><code>text</code></td>
        <td>Second slide headline</td>
        <td><code>Limited Time!</code></td>
    </tr>
    <tr>
        <td><code>ctaSlide2</code></td>
        <td><code>text</code></td>
        <td>Second slide call to action</td>
        <td><code>Shop Now</code></td>
    </tr>
    <tr>
        <td><code>URLSlide2</code></td>
        <td><code>url</code></td>
        <td>Second slide navigation URL</td>
        <td><code>https://example.com/promo2</code></td>
    </tr>
    <tr>
        <td><code>imageSlide3</code></td>
        <td><code>image</code></td>
        <td>Third slide image</td>
        <td><code>https://example.com/promo3.jpg</code></td>
    </tr>
    <tr>
        <td><code>headlineSlide3</code></td>
        <td><code>text</code></td>
        <td>Third slide headline</td>
        <td><code>New Arrivals</code></td>
    </tr>
    <tr>
        <td><code>ctaSlide3</code></td>
        <td><code>text</code></td>
        <td>Third slide call to action</td>
        <td><code>View Collection</code></td>
    </tr>
    <tr>
        <td><code>URLSlide3</code></td>
        <td><code>url</code></td>
        <td>Third slide navigation URL</td>
        <td><code>https://example.com/promo3</code></td>
    </tr>
    <tr>
        <td rowspan="4">
            <code>standard</code>
        </td>
        <td rowspan="4">
            <code>default</code>
        </td>
        <td><code>coverImage</code></td>
        <td><code>image</code></td>
        <td>Summary cover image</td>
        <td><code>https://example.com/ride.jpg</code></td>
        <td rowspan="4">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
                <tr>
                    <td><code>clicks</code></td>
                    <td><code>default</code></td>
                </tr>
            </table>
        </td>
    </tr>
    <tr>
        <td><code>headline</code></td>
        <td><code>text</code></td>
        <td>Summary headline</td>
        <td><code>Trip Complete</code></td>
    </tr>
    <tr>
        <td><code>body</code></td>
        <td><code>textarea</code></td>
        <td>Summary details</td>
        <td><code>20 min ride to Downtown</code></td>
    </tr>
    <tr>
        <td><code>destinationURL</code></td>
        <td><code>url</code></td>
        <td>URL to navigate</td>
        <td><code>https://example.com/trip-details</code></td>
    </tr>
    <tr>
        <td rowspan="1">
            <code>textOnly</code>
        </td>
        <td rowspan="1">
            <code>default</code>
        </td>
        <td><code>text</code></td>
        <td><code>textarea</code></td>
        <td>Text content</td>
        <td><code>Menu item text</code></td>
        <td rowspan="1">
            <table>
                <tr>
                    <th>Type</th>
                    <th>Key</th>
                </tr>
                <tr>
                    <td><code>impressions</code></td>
                    <td><code>default</code></td>
                </tr>
            </table>
        </td>
    </tr>
</table>

### Available Combinations

<table>
    <tr>
        <th>Placement</th>
        <th>Template</th>
        <th>Styles</th>
    </tr>
    <tr>
        <td><code>search</code></td>
        <td><code>imageWithText</code></td>
        <td>
            <code>imageLeft</code><br>
            <code>imageRight</code>
        </td>
    </tr>
    <tr>
        <td rowspan="2"><code>vehicleSelection</code></td>
        <td><code>imageWithText</code></td>
        <td>
            <code>imageLeft</code><br>
            <code>imageRight</code>
        </td>
    </tr>
    <tr>
        <td><code>wideImageOnly</code></td>
        <td><code>default</code></td>
    </tr>
    <tr>
        <td><code>home</code></td>
        <td><code>wideWithCompanion</code></td>
        <td>
            <code>imageLeft</code><br>
            <code>imageRight</code><br>
            <code>wideImageOnly</code>
        </td>
    </tr>
    <tr>
        <td><code>menu</code></td>
        <td><code>textOnly</code></td>
        <td><code>default</code></td>
    </tr>
    <tr>
        <td><code>promotions</code></td>
        <td><code>carousel3Slides</code></td>
        <td><code>default</code></td>
    </tr>
    <tr>
        <td><code>waiting</code></td>
        <td><code>carousel3Slides</code></td>
        <td><code>default</code></td>
    </tr>
    <tr>
        <td><code>rideSummary</code></td>
        <td><code>standard</code></td>
        <td><code>default</code></td>
    </tr>
</table>
