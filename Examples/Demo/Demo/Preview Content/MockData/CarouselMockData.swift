import Foundation

let carouselMockJson = """
    {
      "contents": [
        {
          "key": "imageSlide1",
          "type": "image",
          "value": "https://cdn.admoai.com/demo/01J4BAX1AETV35Z24TXEW952GS.jpg?aspect_ratio=16:9"
        },
        {
          "key": "headlineSlide1",
          "type": "text",
          "value": "Today's Featured Deal"
        },
        {
          "key": "ctaSlide1",
          "type": "text",
          "value": "View Details"
        },
        {
          "key": "URLSlide1",
          "type": "url",
          "value": "https://example.com/offers"
        },
        {
          "key": "imageSlide2",
          "type": "image",
          "value": "https://cdn.admoai.com/demo/01J4BAVR9V4ZJ223KTAYQ0XYMX.jpg?aspect_ratio=16:9"
        },
        {
          "key": "headlineSlide2",
          "type": "text",
          "value": "Limited Time Offer"
        },
        {
          "key": "ctaSlide2",
          "type": "text",
          "value": "See Offer"
        },
        {
          "key": "URLSlide2",
          "type": "url",
          "value": "https://example.com/terms"
        },
        {
          "key": "imageSlide3",
          "type": "image",
          "value": "https://cdn.admoai.com/demo/01J4BAX6V3FG6KFR1CDZ6TMZ9R.jpg?aspect_ratio=16:9"
        },
        {
          "key": "headlineSlide3",
          "type": "text",
          "value": "Don't Miss Out"
        },
        {
          "key": "ctaSlide3",
          "type": "text",
          "value": "Learn More"
        },
        {
          "key": "URLSlide3",
          "type": "url",
          "value": "https://example.com/terms"
        }
      ],
      "advertiser": {
        "name": "AdMoai",
        "legalName": "AdMoai Limited",
        "logoUrl": "https://cdn.admoai.com/mock/logos/01JEPGMJXARVYSJA0CAM9FQ79Y.png"
      },
      "template": {
        "key": "carousel3Slides",
        "style": "default"
      },
      "tracking": {
        "impressions": [
          {
            "key": "slide1",
            "url": "https://example.com/impression1"
          },
          {
            "key": "slide2",
            "url": "https://example.com/impression2"
          },
          {
            "key": "slide3",
            "url": "https://example.com/impression3"
          }
        ],
        "clicks": [
          {
            "key": "slide1",
            "url": "https://example.com/click1"
          },
          {
            "key": "slide2",
            "url": "https://example.com/click2"
          },
          {
            "key": "slide3",
            "url": "https://example.com/click3"
          }
        ],
        "custom": null
      },
      "metadata": {
        "adId": "ad_00GQPK31C0KE5E8TQN5422A3AM",
        "creativeId": "creative_00GQPK31C050ARGW7B3NENPK0D",
        "advertiserId": "advertiser_01JEPGMJXARVYSJA0CAM9FQ79Y",
        "placementId": "placement_00GQPK324NCVX4DHYQ2JRY985S",
        "templateId": "template_00GQPK324NQEP5VBN4EX0B3JMX",
        "priority": "standard",
        "language": "en"
      }
    }
    """
