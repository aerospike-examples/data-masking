# FROM aerospike/aerospike-server-enterprise:8.1.1.0@sha256:304dcc8169014e259521950e89d932e5957529eced5472e6c865a984f13c0dd4-rc20_1
FROM aerospike/aerospike-server-enterprise:8.1.1.0@sha256:304dcc8169014e259521950e89d932e5957529eced5472e6c865a984f13c0dd4


# Remove the template so entrypoint doesn't overwrite our config
RUN rm -f /etc/aerospike/aerospike.template.conf

# Copy our custom configuration
COPY aerospike.conf /etc/aerospike/aerospike.conf
