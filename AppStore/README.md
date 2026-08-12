# Mac App Store submission package

This folder contains the product copy, release notes, and six polished 2880 by 1800 screenshots for the Beddy Butler 2.0.1 update. The live product page should use:

* Marketing URL: https://www.beddybutler.com/
* Support URL: https://www.beddybutler.com/support/
* Privacy policy URL: https://www.beddybutler.com/privacy/
* Primary category: Lifestyle
* Secondary category: Health & Fitness
* Recommended price: Free

Before upload, create the App Store Connect record for bundle identifier com.nellwatson.Beddy-Butler, confirm the app name is available, complete the age rating questionnaire, and accept any pending developer agreements. Those account actions cannot be proven from the source tree.

Validate the local package first:

```sh
python3 Tools/validate_app_store_metadata.py
Tools/app_store_release.sh --preflight 2.0.1 612
```

The metadata validator checks field limits, canonical URLs, privacy wording, screenshot order, image format, image count, and 2880 by 1800 dimensions without third party Python packages. The archive path also runs `Tools/validate_app_bundle.py` before export or upload. Once the version record, signing access, exact candidate approval, and publication authority exist, set `BEDDY_APP_STORE_UPLOAD_APPROVAL` to `APP_STORE_UPLOAD:<40-character-commit>:<version>:<build>`, then use `--upload` to archive, export, and upload through Xcode. Do not upload merely because preflight passes.
