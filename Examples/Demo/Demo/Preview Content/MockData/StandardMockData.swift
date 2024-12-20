import Foundation

let standardMockJson = """
    {
        "contents": [
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
                "key": "destinationURL",
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
            "key": "rideSummary",
            "style": "default"
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
            "templateId": "rideSummary",
            "placementId": "rideSummary",
            "priority": "high",
            "language": "en"
        }
    }
    """
