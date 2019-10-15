./travis_mon patchwork.dpdk.org api.travis-ci.com TOKEN  | \
    grep '^pw|' | while IFS="|" read -r PW pw_instance BUILD series_id SHA shasum result build_url series_name; do
    build_url=$(echo $build_url | sed 's@/build/@https://travis-ci.com/ovsrobot/dpdk/builds/@')

    SERIES_LINE=$(./series_get patchwork.dpdk.org $series_id)
    sid=$(echo $SERIES_LINE | cut -d\| -f1)
    proj=$(echo $SERIES_LINE | cut -d\| -f2)
    url=$(echo $SERIES_LINE | cut -d\| -f3)
    author=$(echo $SERIES_LINE | cut -d\| -f4)
    email=$(echo $SERIES_LINE | cut -d\| -f5)

    patch_id=$(curl -s $url | jq -rc '.patches[-1].id')
    patch_url=$(curl -s $url | jq -rc '.patches[-1].url')

    if [ "$result" == "passed" ]; then
        RESULT="SUCCESS"
    elif [ "$result" == "failed" ]; then
        RESULT="WARNING"
    fi
    echo "(clear result for series_$series_id with $RESULT at url $build_url on patch $patch_id)"

    echo "To: test-report@dpdk.org" > report.eml
    echo "From: robot@bytheb.org" >> report.eml

    if [ "$RESULT" != "SUCCESS" ]; then
        echo "Cc: $author <$email>" >> report.eml
    fi

    echo "Subject: |$RESULT| pw$patch_id $series_name" >> report.eml
    echo "Date: $(date +"%a, %e %b %Y %T %::z")" >> report.eml
    echo "" >> report.eml

    echo "Test-Label: travis-robot" >> report.eml
    echo "Test-Status: $RESULT" >> report.eml
    echo "$patch_url" >> report.eml
    echo "" >> report.eml
    echo "Build URL: $build_url" >> report.eml

    cat report.eml
done
