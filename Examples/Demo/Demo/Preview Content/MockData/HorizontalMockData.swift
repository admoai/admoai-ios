import Foundation

let horizontalMockJson = """
    {
        "contents": [
            {
                "key": "headline",
                "value": "Premium Ride Service - 20% Off Today",
                "type": "text"
            },
            {
                "key": "squareImage",
                "value": "https://picsum.photos/200",
                "type": "image"
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
            "custom": null
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

let horizontalImageOnlyMockJson = """
    {
        "contents": [
            {
                "key": "wideImage",
                "value": "https://picsum.photos/800/200",
                "type": "image"
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
            "custom": null
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

