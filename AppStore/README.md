# Mac App Store submission package

This folder contains the product copy, release notes, and six polished 2880 by 1800 screenshots for the Beddy Butler 2.0.1 update. The live product page should use:

* Marketing URL: https://www.beddybutler.com/
* Support URL: https://www.beddybutler.com/support/
* Privacy policy URL: https://www.beddybutler.com/privacy/
* Primary category: Lifestyle
* Secondary category: Health & Fitness
* Recommended price: Free

Before upload, create the App Store Connect record for bundle identifier com.nellwatson.Beddy-Butler, confirm the app name is available, complete the age rating questionnaire, and accept any pending developer agreements. Those account actions cannot be proven from the source tree.

Run Tools/app_store_release.sh --preflight 2.0.1 611 locally. Once the version record and signing access exist, use --upload to archive, export, and upload through Xcode.
