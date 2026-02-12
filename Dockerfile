# FROM aerospike/aerospike-server-enterprise:8.1.1.0-rc20_1
FROM aerospike/aerospike-server-enterprise:8.1.1.0


# Remove the template so entrypoint doesn't overwrite our config
RUN rm -f /etc/aerospike/aerospike.template.conf

# Copy our custom configuration
COPY aerospike.conf /etc/aerospike/aerospike.conf
