import Foundation

let horizontalWithCompanionMockJson = """
    {
        "contents": [
            {
                "key": "headline",
                "value": "Premium Ride Service - 20% Off Today",
                "type": "text"
            },
            {
                "key": "body",
                "value": "Experience premium rides with exceptional comfort and safety. Book your ride now!",
                "type": "text"
            },
            {
                "key": "squareImage",
                "value": "https://picsum.photos/200",
                "type": "image"
            },
            {
                "key": "coverImage",
                "value": "https://picsum.photos/800/400",
                "type": "image"
            },
            {
                "key": "cta",
                "value": "Book Now",
                "type": "text"
            },
            {
                "key": "buttonColor",
                "value": "#007AFF",
                "type": "text"
            },
            {
                "key": "buttonTextColor",
                "value": "#FFFFFF",
                "type": "text"
            },
            {
                "key": "clickThroughURL",
                "value": "https://example.com/book-ride",
                "type": "url"
            }
        ],
        "advertiser": {
            "name": "Ride Share Co",
            "legalName": "Ride Share Corporation",
            "logoUrl": "https://picsum.photos/200"
        },
        "template": {
            "key": "search",
            "style": "imageRight"
        },
        "tracking": {
            "impressions": [
                {
                    "key": "default",
                    "url": "https://www.example.com/impression"
                }
            ],
            "clicks": [
                {
                    "key": "default",
                    "url": "https://www.example.com/click"
                }
            ],
            "custom": [
                {
                    "key": "companionOpened",
                    "url": "https://www.example.com/custom"
                }
            ]
        },
        "metadata": {
            "adId": "123",
            "creativeId": "456",
            "advertiserId": "789",
            "templateId": "search",
            "placementId": "search",
            "priority": "high",
            "language": "en"
        }
    }
    """

let horizontalWithCompanionImageOnlyMockJson = """
    {
        "contents": [
            {
                "key": "wideImage",
                "value": "https://picsum.photos/800/200",
                "type": "image"
            },
            {
                "key": "coverImage",
                "value": "https://picsum.photos/800/400",
                "type": "image"
            },
            {
                "key": "headline",
                "value": "Your Next Adventure Awaits",
                "type": "text"
            },
            {
                "key": "body",
                "value": "Experience premium rides with exceptional comfort and safety. Book your ride now!",
                "type": "text"
            },
            {
                "key": "cta",
                "value": "Learn More",
                "type": "text"
            },
            {
                "key": "buttonColor",
                "value": "#FF3B30",
                "type": "text"
            }
        ],
        "advertiser": {
            "name": "Ride Share Co",
            "legalName": "Ride Share Corporation",
            "logoUrl": "https://picsum.photos/200"
        },
        "template": {
            "key": "search",
            "style": "wideImageOnly"
        },
        "tracking": {
            "impressions": [
                {
                    "key": "default",
                    "url": "https://www.example.com/impression"
                }
            ],
            "clicks": [
                {
                    "key": "default",
                    "url": "https://www.example.com/click"
                }
            ],
            "custom": [
                {
                    "key": "companionOpened",
                    "url": "https://www.example.com/custom"
                }
            ]
        },
        "metadata": {
            "adId": "123",
            "creativeId": "456",
            "advertiserId": "789",
            "templateId": "search",
            "placementId": "search",
            "priority": "high",
            "language": "en"
        }
    }
    """
